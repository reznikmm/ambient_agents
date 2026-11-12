with Ambient.JSON;
with VSS.Strings;

package Ambient.Types is
   subtype Text is VSS.Strings.Virtual_String;
   type Event_Kind is
     (CI_Failed,
      CI_Passed,
      Issue_Opened,
      Issue_Edited,
      Issue_Comment,
      PR_Opened,
      PR_Comment,
      Timer,
      Answer);
   type Signal is (CI, Issues, PRs);
   type Agent_Event is record
      Id, Source, Login, Subject, Title, Body_Text, URL, Watch : Text;
      Kind                                                     : Event_Kind :=
        Issue_Opened;
      Bot                                                      : Boolean :=
        False;
      At_Time                                                  :
        Long_Long_Integer := 0;
      Routing                                                  : Signal :=
        Issues;
   end record;
   function Decode (Item : JSON.Value) return Agent_Event;
   function Encode (Item : Agent_Event) return JSON.Value;
   function Signal_Of (Item : Agent_Event) return Signal;
   function Name (Kind : Event_Kind) return String;
   function Name (Item : Signal) return String;
   type Worker_Result is record
      Session_Identifier, Summary, Action : Text;
      Reversible                          : Boolean := True;
      Confidence                          : Long_Float := 0.5;
      Wakeup_Minutes                      : Natural := 0;
      Commented                           : Boolean := False;
   end record;
   function Decode_Result (Item : JSON.Value) return Worker_Result;
   function Encode_Result (Item : Worker_Result) return JSON.Value;
   type Statistics is record
      Received,
      Filtered,
      Gate_Calls,
      Ignored,
      Merged,
      Worker_Runs,
      Active_Workers,
      Max_Workers,
      Pings_Sent,
      Pings_Held,
      Timers_Fired,
      Sessions : Natural := 0;
   end record;
   function Encode (Item : Statistics) return JSON.Value;
end Ambient.Types;
