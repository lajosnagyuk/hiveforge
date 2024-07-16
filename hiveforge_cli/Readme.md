# build hiveforgectl binary
```bash
go build -o hiveforgectl
```
# connect to hiveforge-controller
make sure you are connected to the hiveforge-controller
either that it is exposed via ingress or you are port forwarded
set up config.json and place it in current folder or ~/.hiveforge/config.json


# sample commands
hiveforgectl get jobs
hiveforgectl get agents
hiveforgectl describe agent <agent-id>

```
hiveforge_cli % ./hiveforge get agents
Fetching agents...
Retrieved 2 agents. Displaying...
+----+-----------------------------------------------+-----------------------------------------+--------+---------------------+
| ID | Name                                          | Agent ID                                | Status | Last Heartbeat      |
+----+-----------------------------------------------+-----------------------------------------+--------+---------------------+
| 2  | Agent-hiveforge-agent-86c4d698b5-vzswm-e3d96e | hiveforge-agent-86c4d698b5-vzswm-e3d96e | active | 2024-07-06T09:50:20 |
| 1  | Agent-hiveforge-agent-86c4d698b5-87ndj-18f54f | hiveforge-agent-86c4d698b5-87ndj-18f54f | active | 2024-07-06T09:50:20 |
+----+-----------------------------------------------+-----------------------------------------+--------+---------------------+
hiveforge_cli % ./hiveforge describe agent 2
{
  "id": 2,
  "name": "Agent-hiveforge-agent-86c4d698b5-vzswm-e3d96e",
  "agent_id": "hiveforge-agent-86c4d698b5-vzswm-e3d96e",
  "capabilities": [
    "capability1",
    "capability2"
  ],
  "status": "active",
  "last_heartbeat": "2024-07-06T09:50:40",
  "inserted_at": "2024-07-06T09:44:46",
  "updated_at": "2024-07-06T09:50:40"
}
