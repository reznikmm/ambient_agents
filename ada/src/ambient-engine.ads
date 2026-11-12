with Ambient.ACP_Client;
with Ambient.JSON;
with Ambient.State;
with Ambient.Types;
with Chat_Completions_API.Types;
with MCP.Types;
with VSS.Strings;

package Ambient.Engine is
   type Agent is tagged limited private;
   procedure Initialize
     (Self        : in out Agent;
      State_Path  : String := ".data/agent.json";
      Memory_Root : String := "memory";
      Worker_Mode : String := "sim";
      Gate_Mode   : String := "rules";
      Step        : Natural := 8);
   procedure Close (Self : in out Agent);
   procedure Ingest (Self : in out Agent; Event : Types.Agent_Event);
   procedure Replay
     (Self : in out Agent; Events : JSON.Value; Unique : Boolean := False);
   procedure Flush (Self : in out Agent);
   procedure Tick (Self : in out Agent);
   procedure Advance (Self : in out Agent; Minutes : Long_Long_Integer);
   procedure Jump_To (Self : in out Agent; HHMM : String);
   function Now (Self : Agent) return Long_Long_Integer;
   function Snapshot (Self : Agent) return JSON.Value;
   function Updates (Self : Agent) return JSON.Value;
   procedure Clear_Updates (Self : in out Agent);
   function Thread (Self : Agent) return JSON.Value;
   function Watches (Self : Agent) return JSON.Value;
   function Memory_Index (Self : Agent) return JSON.Value;
   function Memory_Read (Self : Agent; Path : String) return String;
   function Pending_Wakeups (Self : Agent) return JSON.Value;
   function Ask_Answer
     (Self : in out Agent; Id : Long_Long_Integer; Yes : Boolean)
      return Boolean;
   function Digest (Self : in out Agent) return Natural;
   procedure Reset (Self : in out Agent);
   procedure Set_Step (Self : in out Agent; Step : Natural);
   procedure Watch
     (Self : in out Agent; What : String; Remove : Boolean := False);
   procedure Schedule
     (Self : in out Agent; Subject, Reason : String; Minutes : Positive);
   function Chat (Self : in out Agent; Message : String) return String;
   function Tool_List return MCP.Types.Tool_Vector;
   function Execute_Tool
     (Self : in out Agent; Name : String; Arguments : JSON.Value)
      return String;
   function Audit (Self : Agent) return JSON.Value;
   function Stats (Self : Agent) return Types.Statistics;
   function Inspection (Self : Agent) return JSON.Value;
private
   type Agent is tagged limited record
      Database                              : State.Store;
      Memory_Root, Worker_Mode, Gate_Mode   : VSS.Strings.Virtual_String;
      Buffer, Event_Views, Update_Log, Runs : JSON.Value := JSON.Array_Value;
      Counters                              : Types.Statistics;
      Offset, Last_Tick, Sequence           : Long_Long_Integer := 0;
      Step                                  : Natural := 8;
      Adapter                               : ACP_Client.Client;
      Conversation                          :
        Chat_Completions_API.Types.ChatCompletionRequestMessage_Vector;
   end record;
end Ambient.Engine;
