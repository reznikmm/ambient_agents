with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ambient.Engine;
with Ambient.JSON;
with Ambient.MCP_Server;
with Ambient.Server;
with Ambient.Support;

procedure Ambient_Workshop is
   use Ambient.Support;
   Agent     : Ambient.Engine.Agent;
   Mode      : constant String :=
     (if Ada.Command_Line.Argument_Count = 0
      then "--serve"
      else Ada.Command_Line.Argument (1));
   Step      : constant Natural :=
     Natural'Value (Environment ("WORKSHOP_STEP", "8"));
   Dashboard : constant Boolean := Mode = "--dashboard";
   Port      : constant Positive :=
     Positive'Value
       (Environment
          ((if Dashboard then "DASHBOARD_PORT" else "PORT"),
           (if Dashboard then "4000" else "4100")));
begin
   if Ada.Command_Line.Argument_Count > 2
     or Mode not in "--serve" | "--dashboard" | "--mcp" | "--replay" | "--help"
   then
      raise Constraint_Error
        with
          "usage: ambient_workshop [--serve | --dashboard | --mcp | --replay FILE]";
   end if;
   if Mode = "--help" then
      Log
        ("Run from the workshop root. Modes: --serve, --dashboard, --mcp, --replay FILE.");
      return;
   end if;
   if not Ada.Directories.Exists ("fixtures/storm.json") then
      raise Constraint_Error
        with
          "run from the ambient-agents-workshop root (fixtures/storm.json is missing)";
   end if;
   Agent.Initialize
     (Environment ("STATE_PATH", ".data/agent.json"),
      Environment ("MEMORY_DIR", "memory"),
      Environment ("WORKER_MODE", "sim"),
      Environment ("GATE_MODE", "rules"),
      Step);
   if Mode = "--mcp" then
      Ambient.MCP_Server.Run (Agent);
   elsif Mode = "--replay" then
      Agent.Replay
        (Ambient.JSON.Parse
           (Read_File
              ((if Ada.Command_Line.Argument_Count = 2
                then Ada.Command_Line.Argument (2)
                else "fixtures/storm.json"))));
      Agent.Flush;
      Log (Ambient.JSON.Encode (Agent.Snapshot));
   else
      Ambient.Server.Run (Agent, Port, Dashboard);
   end if;
   Agent.Close;
exception
   when Error : others =>
      Log ("ambient_workshop: " & Ada.Exceptions.Exception_Message (Error));
      Agent.Close;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Ambient_Workshop;
