This is HiveForge, the highly distributed, Kubernetes based build system built on Elixir and Erlang.

# Legend
Coordinator - The server / controller service. It is responsible for adding and retrieving job information, keep track of Agents. It also handles authentication.
Agent - An agent is a disposable build engine, capable of executing jobs received from the coordinator.
Job - Any build activity. It could be a job triggered in any fashion, regardless of whether that's recurring, based on time or push/merge activity.
Database - The Central Nexus. The database is responsible for serving as a source of truth for all Coordinators.
Frontend - Responsible for user sessions and displaying information retrieved from a Coordinator.

# Design goals
1. Stateless coordinators. I want coordinators to be able to come and go based on service load and other considerations, without having to own the complexity that comes with stateful coordinators, such as leader election or other clustering complexities, persistent storage, etc.
2. Stateless agents. Agents need to be able to spin up and down in a matter of seconds to milliseconds without concern for persistent storage and state. When an agent finishes a job, it needs to be able to fold in immediately upon uploading the artifact.
3. High availability in every component. If I lose a kubernetes node, I want HiveForge to continue operating. If I lose most kubernetes nodes, I want HiveForge to continue operating.
4. Easy configuration. I want agent configuration to be prescriptive, precise and easy to understand.
5. Determinism. When an agent is spun up from a configuration, I want it to be the same as another agent spun up from the same configuration.
6. Powerful horizontal scaling. Running 100 agents must be as simple as running 5, without any concern for the underlying application. As long as Kubernetes resources allow scaling, HiveForge must be able to scale.
7. Pull builds. Controller doesn't push build jobs to agents, they pull it for themselves. This allows tighter security on agents and simpler architecture for the controller.

# Testing and Development notes
```bash
mix deps get
```
1. To run the tests, run `mix test`
2. to run a REPL: `iex -S mix run` and `recompile`
