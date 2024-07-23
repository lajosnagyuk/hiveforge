# .hiveignore Usage Manual

## Introduction

The .hiveignore file is a powerful tool in the HiveForge system that allows you to specify which files and directories should be ignored during the hashing process. This feature is particularly useful for excluding temporary files, build artifacts, or any other content that you don't want to be included in your directory hash and therefore your build pipelines.

## Basic Usage

1. Create a file named `.hiveignore` in any directory within your project.
2. Add patterns to this file, one per line, to specify which files or directories to ignore.
3. The ignore rules apply to the directory containing the .hiveignore file and all its subdirectories.

## Syntax Rules

- Each line in a .hiveignore file specifies a pattern.
- Blank lines are ignored.
- Lines starting with # are treated as comments.
- Patterns support wildcards:
  - `*` matches any sequence of characters except /
  - `?` matches any single character except /
- To ignore a directory and all its contents, add a trailing slash (/) to the pattern.

## Pattern Matching

- Patterns without a slash are matched against the filename only.
- Patterns with a slash are matched against the full path relative to the .hiveignore file's location.

## Inheritance and Precedence

- Ignore rules are inherited by subdirectories.
- Rules in a .hiveignore file in a subdirectory add to (but cannot negate) rules from parent directories.
- In case of conflicts, the more specific (deeper) .hiveignore file takes precedence for adding rules, but cannot un-ignore files ignored by a parent .hiveignore.

## Examples

Here are some example .hiveignore patterns and their effects:

1. Ignore all .log files:
   ```
   *.log
   ```

2. Ignore a specific file:
   ```
   secret.key
   ```

3. Ignore all files in a specific directory:
   ```
   build/*
   ```

4. Ignore all directories named "temp" and their contents:
   ```
   temp/
   ```

5. Ignore all .tmp files in the current directory only:
   ```
   /*.tmp
   ```

6. Ignore all .cache directories, wherever they appear:
   ```
   **/.cache/
   ```

## Advanced Usage Example

Let's consider a project with the following structure:

```
project/
├── .hiveignore
├── src/
│   ├── .hiveignore
│   ├── main.go
│   └── temp/
│       └── debug.log
├── tests/
│   └── test.go
└── build/
    └── output.exe
```

1. Content of /project/.hiveignore:
   ```
   *.log
   build/
   ```

2. Content of /project/src/.hiveignore:
   ```
   temp/
   ```

In this scenario:
- All .log files throughout the project will be ignored due to the root .hiveignore.
- The entire build/ directory will be ignored.
- The src/temp/ directory will be ignored due to the src/.hiveignore file.
- The src/.hiveignore file adds the temp/ rule but cannot un-ignore .log files in the temp directory.

## Best Practices

1. Place a .hiveignore file in your project root to define global ignore rules.
2. Use more specific .hiveignore files in subdirectories for fine-grained control.
3. Keep your ignore patterns as specific as possible to avoid accidentally ignoring important files.
4. Use comments in your .hiveignore files to explain complex patterns or reasoning.
5. Regularly review and update your .hiveignore files as your project structure evolves.

By following these guidelines and understanding how .hiveignore works, you can efficiently manage which files and directories are included in your HiveForge hashing process.