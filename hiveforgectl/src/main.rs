use clap::{Arg, Command};
use reqwest;
use serde::Deserialize;
use serde_json;
use std::env;
use std::fs;
use std::io;

#[derive(Debug, Deserialize)]
struct Config {
    api_endpoint: String,
    port: i32,
    cacert_file: String,
    debug: bool,
}

impl Config {
    fn new(api_endpoint: String, port: i32, cacert_file: String, debug: bool) -> Self {
        Config {
            api_endpoint,
            port,
            cacert_file,
            debug,
        }
    }

    fn load_config() -> io::Result<Self> {
        let config_paths = [
            "config.json".to_string(),
            format!("{}/.hiveforge/config.json", env::var("HOME").unwrap()),
        ];
        let config_path = config_paths
            .iter()
            .find(|&&ref path| fs::metadata(path).is_ok())
            .ok_or(io::Error::new(
                io::ErrorKind::NotFound,
                "Config file not found in current directory or ~/.hiveforge/",
            ))?;
        let config_data = fs::read_to_string(config_path)?;
        let config: Config = serde_json::from_str(&config_data)?;
        Ok(config)
    }
}

#[derive(Debug, Deserialize)]
struct Job {
    id: i32,
    name: String,
    description: String,
    status: String,
    requested_capabilities: Vec<String>,
    inserted_at: String,
    updated_at: String,
}

impl Job {
    fn parse_jobs(json_response: &str) -> Result<Vec<Self>, serde_json::Error> {
        serde_json::from_str(json_response)
    }
}

fn display_jobs(jobs: &[Job]) {
    let headers = ["ID", "Name", "Status", "Inserted At", "Updated At"];
    let mut max_widths = headers.iter().map(|h| h.len()).collect::<Vec<_>>();

    for job in jobs {
        max_widths[0] = max_widths[0].max(job.id.to_string().len());
        max_widths[1] = max_widths[1].max(job.name.len());
        max_widths[2] = max_widths[2].max(job.status.len());
        max_widths[3] = max_widths[3].max(job.inserted_at.len());
        max_widths[4] = max_widths[4].max(job.updated_at.len());
    }

    let separator = format!(
        "+{}+",
        max_widths.iter().map(|&w| "-".repeat(w + 2)).collect::<Vec<_>>().join("+")
    );
    println!("{}", separator);
    println!(
        "|{}|",
        headers
            .iter()
            .zip(&max_widths)
            .map(|(h, &w)| format!(" {:width$} ", h, width = w))
            .collect::<Vec<_>>()
            .join("|")
    );
    println!("{}", separator);

    for job in jobs {
        println!(
            "|{}|",
            [
                job.id.to_string(),
                job.name.clone(),
                job.status.clone(),
                job.inserted_at.clone(),
                job.updated_at.clone()
            ]
            .iter()
            .zip(&max_widths)
            .map(|(v, &w)| format!(" {:width$} ", v, width = w))
            .collect::<Vec<_>>()
            .join("|")
        );
    }

    println!("{}", separator);
}

async fn get_jobs(config: &Config) -> Result<Vec<Job>, Box<dyn std::error::Error>> {
    let url = format!("http://{}:{}/api/v1/jobs", config.api_endpoint, config.port);
    let client = reqwest::Client::new();
    let response = client.get(&url).send().await?;
    let response_text = response.text().await?;
    if config.debug {
        println!("Raw API response:");
        println!("{}", response_text);
    }
    let jobs = Job::parse_jobs(&response_text)?;
    Ok(jobs)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let matches = Command::new("hiveforgectl")
        .version("1.0")
        .author("Your Name <your.email@example.com>")
        .about("Hiveforge CLI Tool")
        .arg(
            Arg::new("debug")
                .short('d')
                .long("debug")
                .help("Enable debug mode")
                .global(true)
                .action(clap::ArgAction::SetTrue),
        )
        .subcommand(
            Command::new("get")
                .about("Get resources")
                .subcommand(Command::new("jobs").about("Get jobs")),
        )
        .get_matches();

    let mut config = Config::load_config()?;
    config.debug = matches.get_flag("debug");

    if let Some(matches) = matches.subcommand_matches("get") {
        if let Some(_) = matches.subcommand_matches("jobs") {
            match get_jobs(&config).await {
                Ok(jobs) => {
                    if jobs.is_empty() {
                        println!("No jobs found.");
                    } else {
                        display_jobs(&jobs);
                    }
                }
                Err(e) => println!("Error: {}", e),
            }
        }
    } else {
        println!("Usage: hiveforgectl get jobs [-d|--debug]");
    }

    Ok(())
}
