with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Ambient.Engine;
with Ambient.JSON;
with Ambient.Support;
with Ambient.Types;

procedure Ambient_Evals is
   use Ambient.JSON, Ambient.Support, Ambient.Types;
   Agent          : Ambient.Engine.Agent;
   JSON_Output    : Boolean := False;
   Step           : Natural := 8;
   Temporary_Name : GNAT.OS_Lib.String_Access;
   Descriptor     : GNAT.OS_Lib.File_Descriptor;
   Deleted        : Boolean;
   Cases          : Value := Array_Value;
   Failed         : Natural := 0;
   procedure Check (Name : String; Passed : Boolean; Detail : String) is
      Success : constant Boolean := Passed and Agent.Stats.Worker_Runs > 0;
   begin
      Append
        (Cases,
         Make_Object
           ([("name", To_JSON_String (Name)),
             ("ok", To_JSON_Boolean (Success)),
             ("detail",
              To_JSON_String
                (if Agent.Stats.Worker_Runs = 0
                 then "nothing reached a worker"
                 else Detail))]));
      if not Success then
         Failed := Failed + 1;
      end if;
   end Check;
   procedure Cleanup is
      use type GNAT.OS_Lib.String_Access;
   begin
      Agent.Close;
      if Temporary_Name /= null then
         if Ada.Directories.Exists (Temporary_Name.all) then
            Ada.Directories.Delete_Tree (Temporary_Name.all);
         end if;
         GNAT.OS_Lib.Free (Temporary_Name);
      end if;
   end Cleanup;
begin
   for J in 1 .. Ada.Command_Line.Argument_Count loop
      if Ada.Command_Line.Argument (J) = "--json" then
         JSON_Output := True;
      elsif Ada.Command_Line.Argument (J) = "--step"
        and J < Ada.Command_Line.Argument_Count
      then
         Step := Natural'Value (Ada.Command_Line.Argument (J + 1));
      end if;
   end loop;
   GNAT.OS_Lib.Create_Temp_File (Descriptor, Temporary_Name);
   GNAT.OS_Lib.Close (Descriptor);
   GNAT.OS_Lib.Delete_File (Temporary_Name.all, Deleted);
   Ada.Directories.Create_Directory (Temporary_Name.all);
   Write_File
     (Temporary_Name.all & "/memory/preferences.md",
      "At most 3 pings a day. Never merge without asking.");
   Write_File
     (Temporary_Name.all & "/memory/watches.md",
      "# Watches"
      & ASCII.LF
      & "- CI fails on main"
      & ASCII.LF
      & "- New issues that need triage"
      & ASCII.LF);
   Agent.Initialize (":memory:", Temporary_Name.all & "/memory", Step => Step);
   Agent.Jump_To ("10:00");
   Agent.Replay (Parse (Read_File ("fixtures/storm.json")));
   Agent.Flush;
   declare
      Runs                      : constant Value := Agent.Audit;
      Sessions                  : Value := Array_Value;
      Seen_Sessions             : Value := Object_Value;
      Noise, Reactions, CI_Runs : Natural := 0;
      Reasons                   : Boolean := True;
      Snapshot                  : constant Value := Agent.Snapshot;
      Events                    : constant Value := Get (Snapshot, "events");
   begin
      for J in 1 .. Length (Runs) loop
         declare
            Event              : constant Agent_Event :=
              Decode (Get (Element (Runs, J), "event"));
            Session_Identifier : constant String :=
              Get_Text (Get (Element (Runs, J), "result"), "sessionId");
            Body_Text          : constant String :=
              Get_Text (Get (Element (Runs, J), "event"), "body");
         begin
            if Event.Bot
              or Event.Kind = Issue_Edited
              or Contains (Body_Text, "<!-- ambient-agent -->")
            then
               Noise := Noise + 1;
            end if;
            if Trim (Body_Text)
               in "+1" | "same here" | "me too" | "thanks!" | "👍"
            then
               Reactions := Reactions + 1;
            end if;
            if Get_Text (Get (Element (Runs, J), "event"), "subject")
              = "ci:main"
            then
               CI_Runs := CI_Runs + 1;
            end if;
            if not Get_Boolean (Seen_Sessions, Session_Identifier) then
               Append (Sessions, To_JSON_String (Session_Identifier));
               Put (Seen_Sessions, Session_Identifier, To_JSON_Boolean (True));
            end if;
         end;
      end loop;
      for J in 1 .. Length (Events) loop
         if Get_Text (Element (Events, J), "stage") = "ignored"
           and Get_Text (Element (Events, J), "reason") = ""
         then
            Reasons := False;
         end if;
      end loop;
      Check
        ("noise: bots, edits and its own posts never reach a worker",
         Noise = 0,
         Trim (Noise'Image) & " noise events reached a worker");
      Check
        ("cost: reaction-only comments are ignored by the gate, with a reason",
         Agent.Stats.Gate_Calls > 0 and Reactions = 0 and Reasons,
         Trim (Reactions'Image) & " reactions reached a worker");
      Check
        ("duplicates: one CI failure, at most two runs",
         CI_Runs <= 2,
         Trim (CI_Runs'Image) & " runs for the same CI failure");
      Check
        ("sessions: one session per signal, never a crowd of workers",
         Length (Sessions) <= 3 and Agent.Stats.Max_Workers <= 3,
         Trim (Length (Sessions)'Image) & " sessions for 3 signals");
      Check
        ("pings: stays within the budget in memory/preferences.md",
         Agent.Stats.Pings_Sent <= 3,
         Trim (Agent.Stats.Pings_Sent'Image) & " pings with a budget of 3");
   end;
   Agent.Advance (11);
   Check
     ("timers: a red CI books its own check-back",
      Agent.Stats.Timers_Fired > 0,
      "red CI never booked a check-back");
   if JSON_Output then
      Ada.Text_IO.Put_Line
        (Encode
           (Make_Object
              ([("passing", To_JSON_Integer (Long_Long_Integer (6 - Failed))),
                ("total", To_JSON_Integer (6)),
                ("cases", Cases),
                ("stats", Ambient.Types.Encode (Agent.Stats))])));
   else
      Ada.Text_IO.Put_Line
        ("storm: 60 events -> worker runs "
         & Trim (Agent.Stats.Worker_Runs'Image)
         & ", gate calls "
         & Trim (Agent.Stats.Gate_Calls'Image)
         & ", pings "
         & Trim (Agent.Stats.Pings_Sent'Image));
      for J in 1 .. Length (Cases) loop
         declare
            Item : constant Value := Element (Cases, J);
         begin
            Ada.Text_IO.Put_Line
              ((if Get_Boolean (Item, "ok") then "PASS " else "FAIL ")
               & Get_Text (Item, "name"));
            if not Get_Boolean (Item, "ok") then
               Ada.Text_IO.Put_Line ("  " & Get_Text (Item, "detail"));
            end if;
         end;
      end loop;
      Ada.Text_IO.Put_Line (Trim (Integer'Image (6 - Failed)) & "/6 passing");
   end if;
   Cleanup;
   if Failed > 0 and not JSON_Output then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Error : others =>
      Log ("ambient_evals: " & Ada.Exceptions.Exception_Information (Error));
      Cleanup;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Ambient_Evals;
