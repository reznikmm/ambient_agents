with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ambient.Models;
with Ambient.Decisions;
with Ambient.Support;

package body Ambient.Engine is
   use JSON, Support, Types;
   use type VSS.Strings.Virtual_String;
   use type Ada.Calendar.Time;
   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of (1970, 1, 1);
   function Now (Self : Agent) return Long_Long_Integer
   is (Long_Long_Integer (Long_Float (Ada.Calendar.Clock - Epoch) * 1000.0)
       + Self.Offset);
   function Day (Self : Agent) return Long_Long_Integer
   is (Self.Now / 86_400_000);
   function Date_Text (Self : Agent) return String
   is (Ada.Calendar.Formatting.Image
         (Epoch + Duration (Self.Now / 1000), Time_Zone => 0) (1 .. 10));
   function Items (Self : Agent; Key : String) return Value is
      Result : constant Value := Self.Database.Get (Key);
   begin
      return (if Result.Is_Empty then Array_Value else Result);
   end Items;
   procedure Emit (Self : in out Agent; Item : Value) is
   begin
      Append (Self.Update_Log, Item);
      Self.Update_Log := State.Tail (Self.Update_Log, 500);
   end Emit;
   procedure Publish (Self : in out Agent) is
   begin
      Emit
        (Self,
         Make_Object
           ([("t", To_JSON_String ("stats")),
             ("stats", Types.Encode (Self.Counters))]));
      Self.Database.Save;
   end Publish;
   procedure View
     (Self   : in out Agent;
      Event  : Agent_Event;
      Stage  : String;
      Reason : String := "")
   is
      Result : Value := Array_Value;
      Item   : constant Value :=
        Make_Object
          ([("id", To_JSON_String (To_UTF_8_String (Event.Id))),
            ("kind", To_JSON_String (Name (Event.Kind))),
            ("subject", To_JSON_String (To_UTF_8_String (Event.Subject))),
            ("title", To_JSON_String (To_UTF_8_String (Event.Title))),
            ("actor", To_JSON_String (To_UTF_8_String (Event.Login))),
            ("stage", To_JSON_String (Stage)),
            ("reason", To_JSON_String (Reason))]);
   begin
      for J in 1 .. Length (Self.Event_Views) loop
         if Get_Text (Element (Self.Event_Views, J), "id")
           /= To_UTF_8_String (Event.Id)
         then
            Append (Result, Element (Self.Event_Views, J));
         end if;
      end loop;
      Append (Result, Item);
      Self.Event_Views := State.Tail (Result, 200);
      Emit
        (Self,
         Make_Object ([("t", To_JSON_String ("event")), ("event", Item)]));
   end View;
   procedure Initialize
     (Self        : in out Agent;
      State_Path  : String := ".data/agent.json";
      Memory_Root : String := "memory";
      Worker_Mode : String := "sim";
      Gate_Mode   : String := "rules";
      Step        : Natural := 8) is
   begin
      if Worker_Mode not in "sim" | "model" | "acp" | "claude" | "auto" then
         raise Constraint_Error
           with "WORKER_MODE must be sim, model, acp, claude or auto";
      end if;
      if Gate_Mode not in "rules" | "model" | "decision" then
         raise Constraint_Error
           with "GATE_MODE must be rules, model or decision";
      end if;
      if Step > 8 then
         raise Constraint_Error with "step must be 0..8";
      end if;
      Self.Database.Open (State_Path);
      Self.Memory_Root := To_Virtual_String (Memory_Root);
      Self.Worker_Mode := To_Virtual_String (Worker_Mode);
      Self.Gate_Mode := To_Virtual_String (Gate_Mode);
      Self.Step := Step;
      Self.Sequence := Get_Integer (Self.Database.Get ("sequence"));
      Self.Last_Tick := Self.Now;
   end Initialize;
   procedure Close (Self : in out Agent) is
   begin
      Self.Adapter.Stop;
      Self.Database.Save;
   end Close;
   function Next_Identifier
     (Self : in out Agent; Prefix : String) return String is
   begin
      Self.Sequence := Self.Sequence + 1;
      Self.Database.Set ("sequence", To_JSON_Integer (Self.Sequence));
      return Prefix & "-" & Image (Self.Now) & "-" & Image (Self.Sequence);
   end Next_Identifier;
   function Thread (Self : Agent) return Value
   is (Items (Self, "thread"));
   function Watches (Self : Agent) return Value
   is (State.Watches (To_UTF_8_String (Self.Memory_Root)));
   function Memory_Index (Self : Agent) return Value
   is (State.Memory_Index (To_UTF_8_String (Self.Memory_Root)));
   function Memory_Read (Self : Agent; Path : String) return String
   is (Read_File (Inside (To_UTF_8_String (Self.Memory_Root), Path)));
   procedure Watch
     (Self : in out Agent; What : String; Remove : Boolean := False) is
   begin
      State.Watch (To_UTF_8_String (Self.Memory_Root), What, Remove);
   end Watch;
   procedure Add_Thread
     (Self           : in out Agent;
      Kind, Text     : String;
      Subject        : String := "";
      Watch          : String := "";
      Ask_Identifier : Long_Long_Integer := 0)
   is
      Entries : constant Value := Self.Thread;
      Result  : Value := Array_Value;
      Item    : Value :=
        Make_Object
          ([("id", To_JSON_String (Next_Identifier (Self, "thread"))),
            ("at", To_JSON_Integer (Self.Now)),
            ("kind", To_JSON_String (Kind)),
            ("text", To_JSON_String (Text))]);
   begin
      if Subject /= "" then
         Put (Item, "subject", To_JSON_String (Subject));
      end if;
      if Watch /= "" then
         Put (Item, "watch", To_JSON_String (Watch));
      end if;
      if Ask_Identifier /= 0 then
         Put (Item, "askId", To_JSON_Integer (Ask_Identifier));
      end if;
      for J in 1 .. Length (Entries) loop
         declare
            Previous : constant Value := Element (Entries, J);
         begin
            if Self.Step >= 5
              and Kind = "report"
              and Get_Text (Previous, "kind") = "report"
              and Get_Text (Previous, "subject") = Subject
            then
               declare
                  History : Value := Get (Previous, "updates");
               begin
                  if History.Is_Empty then
                     History := Array_Value;
                  end if;
                  Append
                    (History,
                     Make_Object
                       ([("at", Get (Previous, "at")),
                         ("text", Get (Previous, "text"))]));
                  Put (Item, "updates", State.Tail (History, 5));
                  Put (Item, "id", Get (Previous, "id"));
               end;
            else
               Append (Result, Previous);
            end if;
         end;
      end loop;
      Append (Result, Item);
      Self.Database.Set ("thread", State.Tail (Result, 300));
   end Add_Thread;
   function Sent_Today (Self : Agent) return Natural is
      Pings : constant Value := Items (Self, "pings");
      Count : Natural := 0;
   begin
      for J in 1 .. Length (Pings) loop
         declare
            Ping : constant Value := Element (Pings, J);
         begin
            if Get_Integer (Ping, "held") = 0
              and Get_Integer (Ping, "at") / 86_400_000 = Self.Day
            then
               Count := Count + 1;
            end if;
         end;
      end loop;
      return Count;
   end Sent_Today;
   function Budget (Self : Agent) return Natural is
      Text        : constant String :=
        Ada.Characters.Handling.To_Lower
          (Read_File (To_UTF_8_String (Self.Memory_Root) & "/preferences.md"));
      At_Most     : constant Natural :=
        Ada.Strings.Fixed.Index (Text, "at most ");
      Start, Last : Natural;
   begin
      if At_Most = 0 then
         return Natural'Last;
      end if;
      Start := At_Most + 8;
      Last := Start;
      while Last <= Text'Last and then Text (Last) in '0' .. '9' loop
         Last := Last + 1;
      end loop;
      if Last = Start then
         return Natural'Last;
      end if;
      return Natural'Value (Text (Start .. Last - 1));
   end Budget;
   procedure Notify (Self : in out Agent; Text : String) is
      pragma Unreferenced (Self);
      URL : constant String := Environment ("SLACK_WEBHOOK_URL");
   begin
      if URL /= "" then
         declare
            Output : constant String :=
              Run
                ("curl",
                 ["--silent",
                  "--show-error",
                  "--fail",
                  "--max-time",
                  "5",
                  "--config",
                  "-"],
                 "url = "
                 & Encode (To_JSON_String (URL))
                 & ASCII.LF
                 & "header = "
                 & Encode (To_JSON_String ("Content-Type: application/json"))
                 & ASCII.LF
                 & "data-binary = "
                 & Encode
                     (To_JSON_String
                        (Encode
                           (Make_Object ([("text", To_JSON_String (Text))]))))
                 & ASCII.LF,
                 Timeout => 6);
            pragma Unreferenced (Output);
         begin
            null;
         end;
      end if;
   exception
      when Error : others =>
         Log
           ("Slack delivery failed: "
            & Ada.Exceptions.Exception_Message (Error));
   end Notify;
   procedure Deliver
     (Self        : in out Agent;
      Event       : Agent_Event;
      Text, Route : String;
      Ping        : Boolean)
   is
      Pings          : Value := Items (Self, "pings");
      Asks           : Value := Items (Self, "asks");
      Ask_Identifier : Long_Long_Integer := 0;
      Actual_Ping    : constant Boolean :=
        Ping and then (Self.Step < 6 or Self.Sent_Today < Self.Budget);
   begin
      if Route = "ask" then
         Self.Sequence := Self.Sequence + 1;
         Ask_Identifier := Self.Sequence;
         Self.Database.Set ("sequence", To_JSON_Integer (Self.Sequence));
         Append
           (Asks,
            Make_Object
              ([("id", To_JSON_Integer (Ask_Identifier)),
                ("subject", To_JSON_String (To_UTF_8_String (Event.Subject))),
                ("signal", To_JSON_String (Name (Event.Routing))),
                ("text", To_JSON_String (Text))]));
         Self.Database.Set ("asks", Asks);
      end if;
      Append
        (Pings,
         Make_Object
           ([("id", To_JSON_String (Next_Identifier (Self, "ping"))),
             ("at", To_JSON_Integer (Self.Now)),
             ("subject", To_JSON_String (To_UTF_8_String (Event.Subject))),
             ("text", To_JSON_String (Text)),
             ("held", To_JSON_Integer (if Actual_Ping then 0 else 1)),
             ("delivered", To_JSON_Integer (0))]));
      Self.Database.Set ("pings", Pings);
      if Actual_Ping or else not Event.Watch.Is_Empty or else Route = "ask"
      then
         Add_Thread
           (Self,
            "report",
            Text,
            To_UTF_8_String (Event.Subject),
            To_UTF_8_String (Event.Watch),
            Ask_Identifier);
      end if;
      if Actual_Ping then
         Self.Counters.Pings_Sent := @ + 1;
         Notify (Self, To_UTF_8_String (Event.Subject) & ": " & Text);
      else
         Self.Counters.Pings_Held := @ + 1;
      end if;
      Emit
        (Self,
         Make_Object
           ([("t", To_JSON_String ("ping")),
             ("subject", To_JSON_String (To_UTF_8_String (Event.Subject))),
             ("text", To_JSON_String (Text)),
             ("route", To_JSON_String (Route)),
             ("ping", To_JSON_Boolean (Actual_Ping))]));
   end Deliver;
   procedure Ingest (Self : in out Agent; Event : Agent_Event) is
      Reason : VSS.Strings.Virtual_String;
   begin
      Self.Counters.Received := @ + 1;
      View (Self, Event, "received");
      if Self.Step >= 4 then
         if Event.Kind = Answer then
            null;
         elsif Event.Bot then
            Reason := "bot";
         elsif Event.Login
           = To_Virtual_String (Environment ("AGENT_LOGIN", "ambient-agent"))
           or Contains (To_UTF_8_String (Event.Body_Text), Self_Marker)
         then
            Reason := "its own post";
         elsif Event.Kind = Issue_Edited then
            Reason := "edit, not new work";
         elsif Event.Kind = CI_Passed then
            Reason := "green build";
         end if;
      end if;
      if not Reason.Is_Empty then
         Self.Counters.Filtered := @ + 1;
         View (Self, Event, "filtered", To_UTF_8_String (Reason));
      elsif Self.Step < 3 then
         View (Self, Event, "received", "heard it; no pipeline yet");
      else
         Append (Self.Buffer, Types.Encode (Event));
      end if;
      Publish (Self);
   end Ingest;
   procedure Replay
     (Self : in out Agent; Events : Value; Unique : Boolean := False)
   is
      Suffix : constant String :=
        (if Unique then Next_Identifier (Self, "replay") else "");
   begin
      if not Is_Array (Events) then
         raise Constraint_Error
           with "replay requires an array of normalized events";
      end if;
      for J in 1 .. Length (Events) loop
         declare
            Event : Agent_Event := Types.Decode (Element (Events, J));
         begin
            if Unique then
               Event.Id := Event.Id & To_Virtual_String ("#" & Suffix);
            end if;
            Event.At_Time := Self.Now;
            Self.Ingest (Event);
         end;
      end loop;
   end Replay;
   function Watch_Matches (Event : Agent_Event; Watch : String) return Boolean
   is
      use Ada.Strings.Unbounded;
      Arrow                        : constant Natural :=
        Ada.Strings.Fixed.Index (Watch, " → ");
      Topic                        : constant String :=
        Ada.Characters.Handling.To_Lower
          ((if Arrow = 0 then Watch else Watch (Watch'First .. Arrow - 1)));
      Stop_Words                   : constant String :=
        " a an the and or of on in to for with about that this any new need needs me my tell watch when it from by pr prs pull request requests ci build builds test tests pipeline pipelines issue issues fail fails failing failed main triage review reviews ";
      Tokens                       : constant String := Topic & " ";
      Word                         : Unbounded_String;
      Has_Topic, Match             : Boolean := False;
      procedure Check_Word is
         Token : constant String := To_String (Word);
      begin
         if Token'Length > 2
           and then not Contains (Stop_Words, " " & Token & " ")
         then
            Has_Topic := True;
            Match :=
              Match
              or Contains
                   (To_UTF_8_String (Event.Title)
                    & " "
                    & To_UTF_8_String (Event.Body_Text),
                    (if Token (Token'Last) = 's'
                     then Token (1 .. Token'Last - 1)
                     else Token));
         end if;
         Word := Null_Unbounded_String;
      end Check_Word;
      PR_Hint, CI_Hint, Issue_Hint : Boolean := False;
   begin
      for C of Tokens loop
         if C in 'a' .. 'z' | '0' .. '9' then
            Append (Word, C);
         else
            declare
               Token : constant String := To_String (Word);
            begin
               PR_Hint := PR_Hint or Token in "pr" | "prs" | "pull";
               CI_Hint :=
                 CI_Hint
                 or Token
                    in "ci"
                     | "build"
                     | "builds"
                     | "test"
                     | "tests"
                     | "pipeline"
                     | "pipelines";
               Issue_Hint := Issue_Hint or Token in "issue" | "issues";
            end;
            Check_Word;
         end if;
      end loop;
      if (PR_Hint or CI_Hint or Issue_Hint)
        and then not ((PR_Hint and Event.Routing = PRs)
                      or (CI_Hint and Event.Routing = CI)
                      or (Issue_Hint and Event.Routing = Issues))
      then
         return False;
      end if;
      return not Has_Topic or Match;
   end Watch_Matches;
   function Rule_Verdict (Self : Agent; Event : Agent_Event) return Value is
      Watches   : constant Value := Self.Watches;
      Body_Text : constant String :=
        Ada.Characters.Handling.To_Lower
          (Trim (To_UTF_8_String (Event.Body_Text)));
      Text      : constant String :=
        To_UTF_8_String (Event.Title) & " " & Body_Text;
   begin
      if Event.Kind in Issue_Comment | PR_Comment
        and then Body_Text
                 in "+1"
                  | "same here"
                  | "me too"
                  | "thanks"
                  | "thanks!"
                  | "thank you"
                  | "thank you!"
                  | "lgtm"
                  | "nice"
                  | "👍"
                  | "🎉"
      then
         return
           Make_Object
             ([("action", To_JSON_String ("ignore")),
               ("reason", To_JSON_String ("reaction-only comment"))]);
      end if;
      if Contains (Text, "delete")
        or Contains (Text, "drop ")
        or Contains (Text, "force-push")
        or Contains (Text, "force push")
        or Contains (Text, "rotate key")
      then
         return
           Make_Object
             ([("action", To_JSON_String ("ask")),
               ("reason", To_JSON_String ("risky request; a human decides"))]);
      end if;
      for J in 1 .. Length (Watches) loop
         if Watch_Matches (Event, Get_Text (Element (Watches, J))) then
            return
              Make_Object
                ([("action", To_JSON_String ("act")),
                  ("reason", To_JSON_String ("new " & Name (Event.Kind))),
                  ("watch", Element (Watches, J))]);
         end if;
      end loop;
      return
        Make_Object
          ([("action", To_JSON_String ("ignore")),
            ("reason", To_JSON_String ("no watch matches"))]);
   end Rule_Verdict;
   function Gate (Self : in out Agent; Batch : Value) return Value is
      Result       : Value := Array_Value;
      Watches      : constant Value := Self.Watches;
      Model_Result : Value;
      Use_Model    : Boolean :=
        To_UTF_8_String (Self.Gate_Mode) /= "rules" and Models.Available;
   begin
      if Self.Step < 4 then
         for J in 1 .. Length (Batch) loop
            Append
              (Result,
               Make_Object
                 ([("action", To_JSON_String ("act")),
                   ("reason", To_JSON_String ("naive pipeline"))]));
         end loop;
         return Result;
      end if;
      Self.Counters.Gate_Calls := @ + 1;
      if Use_Model and To_UTF_8_String (Self.Gate_Mode) /= "decision" then
         begin
            Model_Result :=
              Get
                (Models.Structured
                   ("You gate GitHub events against a person's watches. Return {verdicts:[{i:0,action:act|ignore|ask,watch:0,reason:string}]}. i and watch are zero-based integers, watch may be null. Ignore reactions and unwatched events; ask only for destructive requests. One verdict per event.",
                    Encode
                      (Make_Object
                         ([("watches", Watches), ("events", Batch)])),
                    Environment
                      ("GATE_MODEL",
                       Environment ("CHAT_MODEL", "local-model"))),
                 "verdicts");
         exception
            when Error : others =>
               Log
                 ("gate model failed; using rules: "
                  & Ada.Exceptions.Exception_Message (Error));
               Use_Model := False;
         end;
      end if;
      for J in 1 .. Length (Batch) loop
         declare
            Event    : constant Agent_Event :=
              Types.Decode (Element (Batch, J));
            Verdict  : Value := Rule_Verdict (Self, Event);
            Selected : Value;
         begin
            if To_UTF_8_String (Self.Gate_Mode) = "decision" then
               declare
                  Provider               : constant String :=
                    Environment ("DECISION_PROVIDER", "jev");
                  Questions              : Value :=
                    Make_Object
                      ([("action",
                         Parse
                           ("{""type"":""choice"",""instructions"":""act on work, ignore noise, ask for destructive requests"",""criteria"":{""act"":""real work"",""ignore"":""noise"",""ask"":""destructive""}}"))]);
                  Raw, Answers, Decision : Value;
               begin
                  Self.Counters.Gate_Calls := @ + (if J = 1 then 0 else 1);
                  for Kind in Signal loop
                     Put
                       (Questions,
                        Name (Kind),
                        Make_Object
                          ([("type", To_JSON_String ("noul")),
                            ("instructions",
                             To_JSON_String
                               (case Kind is
                                  when CI     =>
                                    "Is this event about CI, builds, tests or pipelines?",
                                  when Issues =>
                                    "Is this event about an issue, bug report or question?",
                                  when PRs    =>
                                    "Is this event about a pull request or code review?"))]));
                  end loop;
                  for W in 1 .. Length (Watches) loop
                     Put
                       (Questions,
                        "watch" & Image (Long_Long_Integer (W)),
                        Make_Object
                          ([("type", To_JSON_String ("noul")),
                            ("instructions",
                             To_JSON_String
                               ("Is this event about: "
                                & Get_Text (Element (Watches, W))
                                & "?"))]));
                  end loop;
                  Raw :=
                    Decisions.Decide (Provider, Element (Batch, J), Questions);
                  Answers := Get (Raw, "answers");
                  Decision := Get (Answers, "action");
                  if Get_Number (Decision, "confidence")
                    >= Long_Float'Value
                         (Environment ("DECISION_THRESHOLD", "0.6"))
                    and then Get_Text (Decision, "choice")
                             in "act" | "ignore" | "ask"
                  then
                     Selected :=
                       Make_Object
                         ([("action", Get (Decision, "choice")),
                           ("reason",
                            To_JSON_String
                              ("decision: "
                               & Get_Text (Decision, "choice")))]);
                     declare
                        Best : Long_Float := 0.5;
                     begin
                        for Kind in Signal loop
                           if Get_Number (Get (Answers, Name (Kind)), "noul")
                             >= Best
                           then
                              Best :=
                                Get_Number
                                  (Get (Answers, Name (Kind)), "noul");
                              Put
                                (Selected,
                                 "signal",
                                 To_JSON_String (Name (Kind)));
                           end if;
                        end loop;
                     end;
                     for W in 1 .. Length (Watches) loop
                        if Get_Number
                             (Get
                                (Answers,
                                 "watch" & Image (Long_Long_Integer (W))),
                              "noul")
                          >= 0.5
                        then
                           Put
                             (Selected,
                              "watch",
                              To_JSON_Integer (Long_Long_Integer (W - 1)));
                           exit;
                        end if;
                     end loop;
                  elsif Use_Model then
                     Self.Counters.Gate_Calls := @ + 1;
                     Selected :=
                       Models.Structured
                         ("Return {action:act|ignore|ask,watch:zero-based index or null,reason:string}. Match watches, ignore reactions, ask for destructive requests.",
                          Encode
                            (Make_Object
                               ([("event", Element (Batch, J)),
                                 ("watches", Watches)])),
                          Environment ("GATE_MODEL", "local-model"));
                  end if;
               exception
                  when Error : others =>
                     Log
                       ("decision gate failed; using rules: "
                        & Ada.Exceptions.Exception_Message (Error));
               end;
            elsif Use_Model then
               for K in 1 .. Length (Model_Result) loop
                  if Get_Integer (Element (Model_Result, K), "i", -1)
                    = Long_Long_Integer (J - 1)
                  then
                     Selected := Element (Model_Result, K);
                     exit;
                  end if;
               end loop;
            end if;
            if not Selected.Is_Empty
              and then Get_Text (Selected, "action")
                       in "act" | "ignore" | "ask"
            then
               Verdict := Selected;
               declare
                  W : constant Long_Long_Integer :=
                    Get_Integer (Selected, "watch", -1);
               begin
                  if W >= 0 and W < Long_Long_Integer (Length (Watches)) then
                     Put
                       (Verdict, "watch", Element (Watches, Positive (W + 1)));
                  elsif Get_Text (Verdict, "action") /= "ignore" then
                     Verdict :=
                       Make_Object
                         ([("action", To_JSON_String ("ignore")),
                           ("reason", To_JSON_String ("no watch matches"))]);
                  end if;
               end;
            end if;
            Append (Result, Verdict);
         end;
      end loop;
      return Result;
   end Gate;
   function Simulate (Event : Agent_Event) return Worker_Result is
      Result : Worker_Result;
   begin
      case Event.Kind is
         when CI_Failed =>
            Result.Summary :=
              "CI red on main: flaky retry in inbox test. Drafted a fix PR.";
            Result.Action := "draft fix PR";
            Result.Confidence := 0.55;
            Result.Wakeup_Minutes := 10;

         when PR_Opened =>
            Result.Summary :=
              "Reviewed the PR: no blockers, 2 suggestions. Merge?";
            Result.Action := "merge PR";
            Result.Reversible := False;
            Result.Confidence := 0.8;
            Result.Commented := True;

         when Timer     =>
            Result.Summary := "Checked back on CI: the retry passed.";
            Result.Action := "close loop";
            Result.Confidence := 0.9;

         when Answer    =>
            Result.Summary :=
              (if Contains (To_UTF_8_String (Event.Title), "No to:")
               then "Left it as it is, as you said."
               else "Done, as you approved.");
            Result.Action := "carry out";
            Result.Confidence := 1.0;

         when CI_Passed =>
            Result.Summary := "CI is green again.";
            Result.Action := "note";
            Result.Confidence := 0.95;

         when others    =>
            Result.Summary :=
              (if Event.Kind = Issue_Opened
               then "Labelled and triaged the issue, asked for repro steps."
               else "Replied to the comment.");
            Result.Action := "label + comment";
            Result.Confidence := 0.85;
            Result.Commented := True;
      end case;
      return Result;
   end Simulate;
   procedure Schedule
     (Self : in out Agent; Subject, Reason : String; Minutes : Positive)
   is
      Wakeups : Value := Items (Self, "wakeups");
   begin
      Append
        (Wakeups,
         Make_Object
           ([("id", To_JSON_String (Next_Identifier (Self, "wakeup"))),
             ("at",
              To_JSON_Integer
                (Self.Now + Long_Long_Integer (Minutes) * 60_000)),
             ("subject", To_JSON_String (Subject)),
             ("reason", To_JSON_String (Reason)),
             ("fired", To_JSON_Boolean (False))]));
      Self.Database.Set ("wakeups", Wakeups);
      Self.Database.Save;
   end Schedule;
   procedure Work (Self : in out Agent; Event : Agent_Event) is
      Result      : Worker_Result;
      Session_Key : constant String := "session:" & Name (Event.Routing);
      Saved       : constant String :=
        Get_Text (Self.Database.Get (Session_Key));
      Prompt      : constant String :=
        "You look after "
        & Environment ("GITHUB_REPO", "demo/app")
        & ". Signal: "
        & Name (Event.Routing)
        & ASCII.LF
        & "Never merge, close, delete or push. Comments must end with "
        & Self_Marker
        & ". Follow the matching watch instructions. Load and follow the skill below."
        & ASCII.LF
        & Read_File
            (".ruler/skills/"
             & (case Event.Routing is
                  when CI     => "fix-ci",
                  when Issues => "triage-issue",
                  when PRs    => "code-review")
             & "/SKILL.md")
        & ASCII.LF
        & "Finish with one JSON object: {summary:string,action:string,reversible:boolean,confidence:0..1,wakeupInMinutes:optional positive integer,commented:boolean}. No Markdown.";
      Mode        : constant String := To_UTF_8_String (Self.Worker_Mode);
      Route       : VSS.Strings.Virtual_String;
      Ping        : Boolean;
   begin
      Self.Counters.Worker_Runs := @ + 1;
      Self.Counters.Active_Workers := @ + 1;
      Self.Counters.Max_Workers :=
        Natural'Max (Self.Counters.Max_Workers, Self.Counters.Active_Workers);
      View (Self, Event, "working");
      if Mode in "acp" | "claude"
        or else (Mode = "auto" and Event.Source = "github")
      then
         declare
            Response : constant String :=
              Self.Adapter.Prompt
                (Name (Event.Routing),
                 Prompt & ASCII.LF & JSON.Encode (Types.Encode (Event)),
                 Resume_Id =>
                   (if Get_Text
                         (Self.Database.Get
                            ("backend:" & Name (Event.Routing)))
                      = "acp"
                    then Saved
                    else ""));
            Marker   : constant Natural :=
              Ada.Strings.Fixed.Index
                (Response, "RESULT ", Ada.Strings.Backward);
         begin
            Result :=
              Decode_Result
                (Parse
                   (if Marker = 0
                    then Trim (Response)
                    else Trim (Response (Marker + 7 .. Response'Last))));
            Result.Session_Identifier :=
              To_Virtual_String (Self.Adapter.Session (Name (Event.Routing)));
            Self.Database.Set
              ("backend:" & Name (Event.Routing), To_JSON_String ("acp"));
         end;
      elsif Mode = "model" then
         Result :=
           Decode_Result
             (Models.Structured
                (Prompt,
                 "Previous results: "
                 & JSON.Encode
                     (Items (Self, "history:" & Name (Event.Routing)))
                 & ASCII.LF
                 & JSON.Encode (Types.Encode (Event)),
                 Environment
                   ("WORKER_MODEL",
                    Environment ("CHAT_MODEL", "local-model"))));
      else
         Result := Simulate (Event);
      end if;
      if Result.Session_Identifier.Is_Empty then
         Result.Session_Identifier :=
           To_Virtual_String
             (if Saved = "" or Self.Step < 6
              then Next_Identifier (Self, "session-" & Name (Event.Routing))
              else Saved);
      end if;
      Self.Database.Set
        (Session_Key,
         To_JSON_String (To_UTF_8_String (Result.Session_Identifier)));
      Self.Counters.Active_Workers := @ - 1;
      Self.Counters.Sessions := 0;
      for Sig in Signal loop
         if not Self.Database.Get ("session:" & Name (Sig)).Is_Empty then
            Self.Counters.Sessions := @ + 1;
         end if;
      end loop;
      Append
        (Self.Runs,
         Make_Object
           ([("event", Types.Encode (Event)),
             ("result", Encode_Result (Result))]));
      Self.Runs := State.Tail (Self.Runs, 1000);
      declare
         History : Value := Items (Self, "history:" & Name (Event.Routing));
      begin
         Append (History, To_JSON_String (To_UTF_8_String (Result.Summary)));
         Self.Database.Set
           ("history:" & Name (Event.Routing), State.Tail (History, 8));
      end;
      if Self.Step < 6 or Event.Kind = Answer then
         Route := "act";
         Ping := True;
      elsif Result.Reversible and Result.Confidence >= 0.7 then
         Route := "act";
         Ping := False;
      elsif not Result.Reversible and Result.Confidence < 0.7 then
         Route := "note";
         Ping := False;
      else
         Route := (if Result.Reversible then "draft" else "ask");
         Ping := True;
      end if;
      Deliver
        (Self,
         Event,
         To_UTF_8_String (Result.Summary),
         To_UTF_8_String (Route),
         Ping);
      if Self.Step >= 8 then
         State.Remember
           (To_UTF_8_String (Self.Memory_Root),
            To_UTF_8_String (Event.Subject),
            Self.Date_Text,
            To_UTF_8_String (Result.Summary)
            & " → "
            & To_UTF_8_String (Route));
      end if;
      if Self.Step >= 7 and Result.Wakeup_Minutes > 0 then
         Self.Schedule
           (To_UTF_8_String (Event.Subject),
            "check " & To_UTF_8_String (Event.Subject) & " again",
            Result.Wakeup_Minutes);
      end if;
      View (Self, Event, "done", To_UTF_8_String (Result.Summary));
      if Result.Commented and Mode in "sim" | "auto" then
         declare
            Echo : Agent_Event := Event;
         begin
            Echo.Id := To_Virtual_String (Next_Identifier (Self, "echo"));
            Echo.Kind :=
              (if Event.Routing = PRs then PR_Comment else Issue_Comment);
            Echo.Login :=
              To_Virtual_String (Environment ("AGENT_LOGIN", "ambient-agent"));
            Echo.Body_Text :=
              To_Virtual_String
                ("Thanks, I've looked into this. " & Self_Marker);
            Echo.Source := "sim";
            --  Older workshop steps intentionally show the feedback problem.
            if Self.Step >= 4 then
               Self.Ingest (Echo);
            end if;
         end;
      end if;
   exception
      when Error : others =>
         if Self.Counters.Active_Workers > 0 then
            Self.Counters.Active_Workers := @ - 1;
         end if;
         View
           (Self,
            Event,
            "done",
            "failed: " & Ada.Exceptions.Exception_Message (Error));
         Log
           ("worker "
            & To_UTF_8_String (Event.Subject)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
   end Work;
   procedure Offer (Self : in out Agent; Event : Agent_Event) is
      Seen    : Value := Self.Database.Get ("seen");
      Handled : Value := Self.Database.Get ("handled");
      Key     : constant String :=
        To_UTF_8_String (Event.Subject) & "|" & Name (Event.Kind);
      Last    : constant Long_Long_Integer := Get_Integer (Handled, Key, -1);
   begin
      if Self.Step >= 5
        and then (Get_Boolean (Seen, To_UTF_8_String (Event.Id))
                  or else (Event.Kind /= Answer
                           and Last >= 0
                           and Self.Now >= Last
                           and Self.Now - Last < 300_000))
      then
         Self.Counters.Merged := @ + 1;
         View
           (Self,
            Event,
            "merged",
            "joined " & To_UTF_8_String (Event.Subject));
         return;
      end if;
      Put (Seen, To_UTF_8_String (Event.Id), To_JSON_Boolean (True));
      Put (Handled, Key, To_JSON_Integer (Self.Now));
      Self.Database.Set ("seen", Seen);
      Self.Database.Set ("handled", Handled);
      View (Self, Event, "queued");
      Work (Self, Event);
   end Offer;
   procedure Flush (Self : in out Agent) is
      Batch    : constant Value := Self.Buffer;
      Verdicts : Value;
   begin
      Self.Buffer := Array_Value;
      if Length (Batch) = 0 then
         return;
      end if;
      Verdicts := Gate (Self, Batch);
      for J in 1 .. Length (Batch) loop
         declare
            Event   : Agent_Event := Types.Decode (Element (Batch, J));
            Verdict : constant Value := Element (Verdicts, J);
            Action  : constant String := Get_Text (Verdict, "action");
         begin
            Event.Watch := To_Virtual_String (Get_Text (Verdict, "watch"));
            if Get_Text (Verdict, "signal") in "ci" | "issues" | "prs" then
               Event.Routing := Signal'Value (Get_Text (Verdict, "signal"));
            end if;
            if Action = "ignore" then
               Self.Counters.Ignored := @ + 1;
               View (Self, Event, "ignored", Get_Text (Verdict, "reason"));
            elsif Action = "ask" then
               Deliver
                 (Self,
                  Event,
                  "Before I touch "
                  & To_UTF_8_String (Event.Title)
                  & ": "
                  & Get_Text (Verdict, "reason")
                  & ". Go ahead?",
                  "ask",
                  True);
               View (Self, Event, "done", Get_Text (Verdict, "reason"));
            else
               Offer (Self, Event);
            end if;
         end;
      end loop;
      Publish (Self);
   end Flush;
   function Ask_Answer
     (Self : in out Agent; Id : Long_Long_Integer; Yes : Boolean)
      return Boolean
   is
      Asks      : constant Value := Items (Self, "asks");
      Remaining : Value := Array_Value;
      Found     : Value;
   begin
      for J in 1 .. Length (Asks) loop
         if Get_Integer (Element (Asks, J), "id") = Id then
            Found := Element (Asks, J);
         else
            Append (Remaining, Element (Asks, J));
         end if;
      end loop;
      if Found.Is_Empty then
         return False;
      end if;
      Self.Database.Set ("asks", Remaining);
      declare
         Event : Agent_Event;
      begin
         Event.Id := To_Virtual_String (Next_Identifier (Self, "answer"));
         Event.Source := "you";
         Event.Login := "you";
         Event.Kind := Answer;
         Event.Subject := To_Virtual_String (Get_Text (Found, "subject"));
         Event.Title :=
           To_Virtual_String
             ((if Yes then "Yes to: " else "No to: ")
              & Get_Text (Found, "text"));
         Event.Routing := Signal'Value (Get_Text (Found, "signal"));
         Event.At_Time := Self.Now;
         Self.Counters.Received := @ + 1;
         Offer (Self, Event);
      end;
      Publish (Self);
      return True;
   end Ask_Answer;
   function Pending_Wakeups (Self : Agent) return Value is
      All_Items : constant Value := Items (Self, "wakeups");
      Result    : Value := Array_Value;
   begin
      for J in 1 .. Length (All_Items) loop
         if not Get_Boolean (Element (All_Items, J), "fired") then
            Append (Result, Element (All_Items, J));
         end if;
      end loop;
      return Result;
   end Pending_Wakeups;
   function Digest (Self : in out Agent) return Natural is
      Pings  : constant Value := Items (Self, "pings");
      Result : Value := Array_Value;
      Count  : Natural := 0;
      Text   : VSS.Strings.Virtual_String;
   begin
      for J in 1 .. Length (Pings) loop
         declare
            Ping : Value := Element (Pings, J);
         begin
            if Get_Integer (Ping, "held") = 1
              and Get_Integer (Ping, "delivered") = 0
            then
               Count := Count + 1;
               Text.Append
                 (To_Virtual_String
                    ("- "
                     & Get_Text (Ping, "subject")
                     & ": "
                     & Get_Text (Ping, "text")
                     & ASCII.LF));
               Put (Ping, "delivered", To_JSON_Integer (1));
            end if;
            Append (Result, Ping);
         end;
      end loop;
      Self.Database.Set ("pings", Result);
      if Count > 0 then
         Add_Thread
           (Self,
            "digest",
            "Digest, "
            & Trim (Count'Image)
            & " items:"
            & ASCII.LF
            & To_UTF_8_String (Text));
         Notify (Self, To_UTF_8_String (Text));
      end if;
      Emit
        (Self,
         Make_Object
           ([("t", To_JSON_String ("digest")),
             ("items", To_JSON_Integer (Long_Long_Integer (Count)))]));
      Self.Database.Save;
      return Count;
   end Digest;
   procedure Tick (Self : in out Agent) is
      Wakeups : constant Value := Items (Self, "wakeups");
      Result  : Value := Array_Value;
      Due     : Value := Array_Value;
      Nine    : constant Long_Long_Integer :=
        Self.Day * 86_400_000 + 9 * 3_600_000;
   begin
      if Self.Step < 7 then
         return;
      end if;
      for J in 1 .. Length (Wakeups) loop
         declare
            Item : Value := Element (Wakeups, J);
         begin
            if not Get_Boolean (Item, "fired")
              and Get_Integer (Item, "at") <= Self.Now
            then
               Append (Due, Item);
               Put (Item, "fired", To_JSON_Boolean (True));
            end if;
            Append (Result, Item);
         end;
      end loop;
      Self.Database.Set ("wakeups", Result);
      for J in 1 .. Length (Due) loop
         declare
            Item  : constant Value := Element (Due, J);
            Event : Agent_Event;
         begin
            Event.Id := To_Virtual_String (Get_Text (Item, "id"));
            Event.Kind := Timer;
            Event.Source := "timer";
            Event.Login := "clock";
            Event.Subject := To_Virtual_String (Get_Text (Item, "subject"));
            Event.Title := To_Virtual_String (Get_Text (Item, "reason"));
            Event.At_Time := Self.Now;
            Event.Routing := Signal_Of (Event);
            Self.Counters.Timers_Fired := @ + 1;
            if Contains (To_UTF_8_String (Event.Title), "Reminder:") then
               Self.Counters.Received := @ + 1;
               Deliver
                 (Self, Event, To_UTF_8_String (Event.Title), "note", True);
               View (Self, Event, "done", "your reminder");
            else
               Self.Ingest (Event);
            end if;
         end;
      end loop;
      if Self.Last_Tick < Nine and Self.Now >= Nine then
         declare
            Count : constant Natural := Self.Digest;
            pragma Unreferenced (Count);
         begin
            null;
         end;
      end if;
      Self.Last_Tick := Self.Now;
      Publish (Self);
   end Tick;
   procedure Advance (Self : in out Agent; Minutes : Long_Long_Integer) is
   begin
      if Minutes not in -5_256_000 .. 5_256_000 then
         raise Constraint_Error
           with "advanceMinutes must be -5256000..5256000";
      end if;
      Self.Offset := @ + Minutes * 60_000;
      Self.Tick;
      Self.Flush;
   end Advance;
   procedure Jump_To (Self : in out Agent; HHMM : String) is
      Colon          : constant Natural := Ada.Strings.Fixed.Index (HHMM, ":");
      Hours, Minutes : Natural;
      Target         : Long_Long_Integer;
   begin
      if Colon = 0 then
         raise Constraint_Error with "time must be HH:MM";
      end if;
      Hours := Natural'Value (HHMM (HHMM'First .. Colon - 1));
      Minutes := Natural'Value (HHMM (Colon + 1 .. HHMM'Last));
      if Hours > 23 or Minutes > 59 then
         raise Constraint_Error with "time must be HH:MM";
      end if;
      Target :=
        Self.Day
        * 86_400_000
        + Long_Long_Integer (Hours * 60 + Minutes) * 60_000;
      if Target <= Self.Now then
         Target := Target + 86_400_000;
      end if;
      Self.Offset := @ + Target - Self.Now;
   end Jump_To;
   function Stats (Self : Agent) return Statistics
   is (Self.Counters);
   function Audit (Self : Agent) return Value
   is (Self.Runs);
   function Snapshot (Self : Agent) return Value is
   begin
      return
        Make_Object
          ([("instance",
             To_JSON_String (Environment ("INSTANCE", "ambient-ada"))),
            ("ref", To_JSON_String ("step-" & Trim (Self.Step'Image))),
            ("port",
             To_JSON_Integer
               (Long_Long_Integer'Value (Environment ("PORT", "4100")))),
            ("workerMode",
             To_JSON_String (To_UTF_8_String (Self.Worker_Mode))),
            ("gateMode", To_JSON_String (To_UTF_8_String (Self.Gate_Mode))),
            ("repo", To_JSON_String (Environment ("GITHUB_REPO"))),
            ("stats", Types.Encode (Self.Counters)),
            ("clock", To_JSON_Integer (Self.Now)),
            ("budget",
             (if Self.Budget = Natural'Last
              then Null_Value
              else To_JSON_Integer (Long_Long_Integer (Self.Budget)))),
            ("pings", State.Tail (Items (Self, "pings"), 20)),
            ("wakeups", Self.Pending_Wakeups),
            ("events", State.Tail (Self.Event_Views, 60)),
            ("asks", Items (Self, "asks"))]);
   end Snapshot;
   function Updates (Self : Agent) return Value
   is (Self.Update_Log);
   procedure Clear_Updates (Self : in out Agent) is
   begin
      Self.Update_Log := Array_Value;
   end Clear_Updates;
   procedure Reset (Self : in out Agent) is
      use Ada.Directories;
   begin
      Self.Adapter.Stop;
      Self.Database.Reset;
      Self.Buffer := Array_Value;
      Self.Event_Views := Array_Value;
      Self.Update_Log := Array_Value;
      Self.Runs := Array_Value;
      Self.Conversation := [];
      Self.Counters := (others => 0);
      if Self.Step >= 8 then
         for Index in 1 .. 2 loop
            declare
               Path : constant String :=
                 Inside
                   (To_UTF_8_String (Self.Memory_Root),
                    (if Index = 1 then "journal" else "subjects"));
            begin
               if Exists (Path) then
                  Delete_Tree (Path);
               end if;
            end;
         end loop;
      end if;
      Publish (Self);
   end Reset;
   procedure Set_Step (Self : in out Agent; Step : Natural) is
   begin
      if Step > 8 then
         raise Constraint_Error with "step must be 0..8";
      end if;
      Self.Step := Step;
      Self.Reset;
   end Set_Step;
   function Tool_List return MCP.Types.Tool_Vector is
      Result       : MCP.Types.Tool_Vector;
      procedure Add_Tool (Name, Description, Schema : String) is
         Tool : MCP.Types.Tool;
      begin
         Tool.name := To_Virtual_String (Name);
         Tool.description := To_Virtual_String (Description);
         for Event of Parse (Schema) loop
            Tool.inputSchema.Append (Event);
         end loop;
         Result.Append (Tool);
      end Add_Tool;
      Path_Schema  : constant String :=
        "{""type"":""object"",""properties"":{""path"":{""type"":""string""}},""required"":[""path""]}";
      What_Schema  : constant String :=
        "{""type"":""object"",""properties"":{""what"":{""type"":""string""},""then"":{""type"":""string""}},""required"":[""what""]}";
      Empty_Schema : constant String :=
        "{""type"":""object"",""properties"":{}}";
   begin
      Add_Tool
        ("list_files",
         "List files and folders inside the checkout.",
         Path_Schema);
      Add_Tool
        ("read_file", "Read a UTF-8 file inside the checkout.", Path_Schema);
      Add_Tool
        ("search",
         "Search tracked files using a regular expression.",
         "{""type"":""object"",""properties"":{""pattern"":{""type"":""string""}},""required"":[""pattern""]}");
      Add_Tool
        ("github_issues",
         "List issues in the configured GitHub repo.",
         "{""type"":""object"",""properties"":{""state"":{""type"":""string"",""enum"":[""open"",""closed"",""all""]}}}");
      Add_Tool
        ("github_issue",
         "Read one issue and its comments.",
         "{""type"":""object"",""properties"":{""number"":{""type"":""integer"",""minimum"":1}},""required"":[""number""]}");
      Add_Tool ("github_prs", "List open pull requests.", Empty_Schema);
      Add_Tool ("github_runs", "List recent CI runs.", Empty_Schema);
      Add_Tool
        ("load_skill",
         "Load instructions for a job from .ruler/skills.",
         "{""type"":""object"",""properties"":{""name"":{""type"":""string""}},""required"":[""name""]}");
      Add_Tool
        ("watch",
         "Watch a topic; optionally give an instruction in then.",
         What_Schema);
      Add_Tool ("unwatch", "Remove a standing watch.", What_Schema);
      Add_Tool
        ("recent_activity", "Recent events and notifications.", Empty_Schema);
      Add_Tool
        ("remind",
         "Set a reminder in minutes or at HH:MM on the agent's UTC clock.",
         "{""type"":""object"",""properties"":{""what"":{""type"":""string""},""inMinutes"":{""type"":""integer"",""minimum"":1},""at"":{""type"":""string""}},""required"":[""what""]}");
      Add_Tool
        ("memory_read", "Read one file from the memory index.", Path_Schema);
      Add_Tool
        ("memory_write",
         "Replace a memory file, including preferences.md.",
         "{""type"":""object"",""properties"":{""path"":{""type"":""string""},""content"":{""type"":""string""}},""required"":[""path"",""content""]}");
      Add_Tool
        ("memory_append",
         "Append one line to a memory file.",
         "{""type"":""object"",""properties"":{""path"":{""type"":""string""},""line"":{""type"":""string""}},""required"":[""path"",""line""]}");
      if Environment ("CHAT_CAN_COMMENT") = "1"
        and Environment ("GITHUB_REPO") /= ""
      then
         Add_Tool
           ("github_comment",
            "Post a comment in the configured repo only when explicitly requested.",
            "{""type"":""object"",""properties"":{""number"":{""type"":""integer"",""minimum"":1},""body"":{""type"":""string""}},""required"":[""number"",""body""]}");
      end if;
      return Result;
   end Tool_List;
   function Execute_Tool
     (Self : in out Agent; Name : String; Arguments : Value) return String
   is
      use Ada.Directories;
      Path : constant String := Get_Text (Arguments, "path");
      Repo : constant String := Environment ("GITHUB_REPO");
      function Required_Text (Key : String) return String is
      begin
         if not Is_String (Get (Arguments, Key)) then
            raise Constraint_Error with "tool requires string " & Key;
         end if;
         return Get_Text (Arguments, Key);
      end Required_Text;
   begin
      if not Is_Object (Arguments) then
         raise Constraint_Error with "tool arguments must be an object";
      end if;
      if Name = "read_file" then
         return Read_File (Inside (Current_Directory, Required_Text ("path")));
      elsif Name = "list_files" then
         declare
            Search     : Search_Type;
            Entry_Item : Directory_Entry_Type;
            Result     : VSS.Strings.Virtual_String;
         begin
            Start_Search
              (Search,
               Inside (Current_Directory, (if Path = "" then "." else Path)),
               "*");
            while More_Entries (Search) loop
               Get_Next_Entry (Search, Entry_Item);
               if Simple_Name (Entry_Item)
                  not in "." | ".." | ".git" | "node_modules"
               then
                  Result.Append
                    (To_Virtual_String
                       (Simple_Name (Entry_Item)
                        & (if Kind (Entry_Item) = Directory then "/" else "")
                        & ASCII.LF));
               end if;
            end loop;
            End_Search (Search);
            return To_UTF_8_String (Result);
         end;
      elsif Name = "search" then
         return
           Run
             ("git",
              ["grep",
               "-n",
               "-E",
               "--",
               To_Virtual_String (Required_Text ("pattern"))]);
      elsif Name = "load_skill" then
         return
           Read_File
             (Inside (".ruler/skills", Required_Text ("name") & "/SKILL.md"),
              "no such skill");
      elsif Name in "watch" | "unwatch" then
         Self.Watch
           (Required_Text ("what")
            & (if Get_Text (Arguments, "then") = ""
               then ""
               else " → " & Get_Text (Arguments, "then")),
            Name = "unwatch");
         return Encode (Self.Watches);
      elsif Name = "recent_activity" then
         return Encode (Self.Snapshot);
      elsif Name = "memory_read" then
         return Self.Memory_Read (Required_Text ("path"));
      elsif Name = "memory_write" then
         Write_File
           (Inside
              (To_UTF_8_String (Self.Memory_Root), Required_Text ("path")),
            Required_Text ("content"));
         return "saved " & Path;
      elsif Name = "memory_append" then
         Append_File
           (Inside
              (To_UTF_8_String (Self.Memory_Root), Required_Text ("path")),
            Required_Text ("line") & ASCII.LF);
         return "appended " & Path;
      elsif Name = "remind" then
         declare
            Minutes : Long_Long_Integer :=
              Get_Integer (Arguments, "inMinutes");
            At_Time : constant String := Get_Text (Arguments, "at");
         begin
            if Minutes = 0 and At_Time /= "" then
               declare
                  Colon         : constant Natural :=
                    Ada.Strings.Fixed.Index (At_Time, ":");
                  Hours, Minute : Natural;
                  Due           : Long_Long_Integer;
               begin
                  if Colon = 0 then
                     raise Constraint_Error with "at must be HH:MM";
                  end if;
                  Hours :=
                    Natural'Value (At_Time (At_Time'First .. Colon - 1));
                  Minute :=
                    Natural'Value (At_Time (Colon + 1 .. At_Time'Last));
                  if Hours > 23 or Minute > 59 then
                     raise Constraint_Error with "at must be HH:MM";
                  end if;
                  Due :=
                    Self.Day
                    * 86_400_000
                    + Long_Long_Integer (Hours * 60 + Minute) * 60_000;
                  if Due <= Self.Now then
                     Due := Due + 86_400_000;
                  end if;
                  Minutes := (Due - Self.Now + 59_999) / 60_000;
               end;
            end if;
            if Minutes not in 1 .. 525_600 then
               raise Constraint_Error
                 with "reminder needs inMinutes (1..525600) or at (HH:MM)";
            end if;
            Self.Schedule
              ("reminders",
               "Reminder: " & Required_Text ("what"),
               Positive (Minutes));
            return "Reminder set in " & Image (Minutes) & " minutes.";
         end;
      elsif Name
            in "github_issues"
             | "github_issue"
             | "github_prs"
             | "github_runs"
             | "github_comment"
      then
         if Repo = "" then
            return "No GitHub repo connected (set GITHUB_REPO).";
         end if;
         if Name = "github_issues" then
            declare
               State_Name : constant String := Get_Text (Arguments, "state");
            begin
               if State_Name /= ""
                 and State_Name not in "open" | "closed" | "all"
               then
                  raise Constraint_Error
                    with "state must be open, closed or all";
               end if;
               return
                 Run
                   ("gh",
                    ["issue",
                     "list",
                     "--repo",
                     To_Virtual_String (Repo),
                     "--state",
                     To_Virtual_String
                       (if State_Name = "" then "open" else State_Name),
                     "--limit",
                     "20"]);
            end;
         elsif Name = "github_prs" then
            return
              Run
                ("gh",
                 ["pr",
                  "list",
                  "--repo",
                  To_Virtual_String (Repo),
                  "--limit",
                  "20"]);
         elsif Name = "github_runs" then
            return
              Run
                ("gh",
                 ["run",
                  "list",
                  "--repo",
                  To_Virtual_String (Repo),
                  "--limit",
                  "10"]);
         else
            if Get_Integer (Arguments, "number") <= 0 then
               raise Constraint_Error with "number must be a positive integer";
            end if;
            if Name = "github_issue" then
               return
                 Run
                   ("gh",
                    ["issue",
                     "view",
                     To_Virtual_String
                       (Image (Get_Integer (Arguments, "number"))),
                     "--repo",
                     To_Virtual_String (Repo),
                     "--comments"]);
            elsif Environment ("CHAT_CAN_COMMENT") = "1" then
               return
                 Run
                   ("gh",
                    ["issue",
                     "comment",
                     To_Virtual_String
                       (Image (Get_Integer (Arguments, "number"))),
                     "--repo",
                     To_Virtual_String (Repo),
                     "--body-file",
                     "-"],
                    Required_Text ("body")
                    & ASCII.LF
                    & ASCII.LF
                    & Self_Marker);
            else
               raise Constraint_Error with "github_comment is disabled";
            end if;
         end if;
      else
         raise Constraint_Error with "unknown tool: " & Name;
      end if;
   end Execute_Tool;
   function Chat (Self : in out Agent; Message : String) return String is
      use Chat_Completions_API.Types;
      Output   : VSS.Strings.Virtual_String;
      Messages : ChatCompletionRequestMessage_Vector;
      Tools    : ChatCompletionTool_Vector;
      Catalog  : constant MCP.Types.Tool_Vector := Tool_List;
      procedure Part (Item : Value) is
      begin
         Output.Append (To_Virtual_String (Encode (Item) & ASCII.LF));
      end Part;
   begin
      Add_Thread (Self, "you", Message);
      if Self.Step = 0 or not Models.Available then
         declare
            Reply : constant String :=
              (if Self.Step = 0
               then "I am not built yet (step 1)."
               else
                 "Set CHAT_COMPLETIONS_URL and CHAT_MODEL, or an API key, to enable chat. Events and simulated workers are available without credentials.");
         begin
            Part
              (Make_Object
                 ([("t", To_JSON_String ("text")),
                   ("text", To_JSON_String (Reply))]));
            Add_Thread (Self, "agent", Reply);
         end;
      else
         for J in 1 .. Catalog.Length loop
            declare
               Item   : ChatCompletionTool;
               Schema : FunctionParameters;
            begin
               for Event of Catalog (J).inputSchema loop
                  Schema.Append (Event);
               end loop;
               Item.a_function.name := Catalog (J).name;
               Item.a_function.description := Catalog (J).description;
               Item.a_function.parameters := (Is_Set => True, Value => Schema);
               Tools.Append (Item);
            end;
         end loop;
         --  Trim only at user boundaries so tool calls retain their results.
         if Self.Conversation.Length > 24 then
            declare
               Start  : Positive := Self.Conversation.Length - 23;
               Recent : ChatCompletionRequestMessage_Vector;
            begin
               while Start <= Self.Conversation.Length
                 and then Self.Conversation (Start).role /= user
               loop
                  Start := Start + 1;
               end loop;
               for J in Start .. Self.Conversation.Length loop
                  Recent.Append (Self.Conversation (J));
               end loop;
               Self.Conversation := Recent;
            end;
         end if;
         Messages.Append
           ((role    => system,
             content =>
               To_Virtual_String
                 ("You are the ambient engineering agent for "
                  & Environment ("GITHUB_REPO", "this checkout")
                  & ". Use tools to inspect before answering. Load skills before doing jobs. Never merge, close, delete or push. Keep replies short. Record lasting preferences in memory."
                  & ASCII.LF
                  & "Agent UTC clock milliseconds: "
                  & Image (Self.Now)
                  & ASCII.LF
                  & "Watches: "
                  & Encode (Self.Watches)
                  & ASCII.LF
                  & "Preferences: "
                  & Read_File
                      (To_UTF_8_String (Self.Memory_Root) & "/preferences.md")
                  & ASCII.LF
                  & "Memory index (read on demand): "
                  & Encode (Self.Memory_Index)
                  & ASCII.LF
                  & "Recent reports: "
                  & Encode (State.Tail (Self.Thread, 8))),
             others  => <>));
         for J in 1 .. Self.Conversation.Length loop
            Messages.Append (Self.Conversation (J));
         end loop;
         Messages.Append
           ((role    => user,
             content => To_Virtual_String (Message),
             others  => <>));
         for Turn in 1 .. 10 loop
            declare
               Response : constant ChatCompletionResponseMessage :=
                 Models.Complete (Messages, Tools);
            begin
               Messages.Append
                 ((role       => assistant,
                   content    => Response.content,
                   tool_calls => Response.tool_calls,
                   others     => <>));
               if not Response.content.Is_Empty then
                  Part
                    (Make_Object
                       ([("t", To_JSON_String ("text")),
                         ("text",
                          To_JSON_String
                            (To_UTF_8_String (Response.content)))]));
               end if;
               for J in 1 .. Response.tool_calls.Length loop
                  declare
                     Call   : constant ChatCompletionMessageToolCall :=
                       Response.tool_calls (J);
                     Result : VSS.Strings.Virtual_String;
                  begin
                     Part
                       (Make_Object
                          ([("t", To_JSON_String ("tool")),
                            ("name",
                             To_JSON_String
                               (To_UTF_8_String (Call.a_function.name))),
                            ("input",
                             Parse
                               (To_UTF_8_String
                                  (Call.a_function.arguments)))]));
                     begin
                        Result :=
                          To_Virtual_String
                            (Self.Execute_Tool
                               (To_UTF_8_String (Call.a_function.name),
                                Parse
                                  (To_UTF_8_String
                                     (Call.a_function.arguments))));
                     exception
                        when Error : others =>
                           Result :=
                             To_Virtual_String
                               ("tool failed: "
                                & Ada.Exceptions.Exception_Message (Error));
                     end;
                     declare
                        Text    : constant String := To_UTF_8_String (Result);
                        Clipped : constant String :=
                          Text
                            (Text'First
                             .. Natural'Min (Text'Last, Text'First + 11_999));
                     begin
                        Part
                          (Make_Object
                             ([("t", To_JSON_String ("tool-result")),
                               ("name",
                                To_JSON_String
                                  (To_UTF_8_String (Call.a_function.name))),
                               ("output", To_JSON_String (Clipped))]));
                        Messages.Append
                          ((role         => tool,
                            tool_call_id => Call.id,
                            content      => To_Virtual_String (Clipped),
                            others       => <>));
                     end;
                  end;
               end loop;
               if Response.tool_calls.Length = 0 then
                  Add_Thread
                    (Self, "agent", To_UTF_8_String (Response.content));
                  exit;
               elsif Turn = 10 then
                  Part
                    (Make_Object
                       ([("t", To_JSON_String ("error")),
                         ("error",
                          To_JSON_String
                            ("Tool loop reached 10 turns; ask to continue."))]));
               end if;
            end;
         end loop;
         Self.Conversation := [];
         for J in 2 .. Messages.Length loop
            Self.Conversation.Append (Messages (J));
         end loop;
      end if;
      Self.Database.Save;
      Part (Make_Object ([("t", To_JSON_String ("done"))]));
      return To_UTF_8_String (Output);
   exception
      when Error : others =>
         Part
           (Make_Object
              ([("t", To_JSON_String ("error")),
                ("error",
                 To_JSON_String (Ada.Exceptions.Exception_Message (Error)))]));
         Part (Make_Object ([("t", To_JSON_String ("done"))]));
         Self.Database.Save;
         return To_UTF_8_String (Output);
   end Chat;
   function Inspection (Self : Agent) return Value is
      Data       : constant Value := Self.Database.Contents;
      Keys       : constant Value := Member_Names (Data);
      Tables     : Value := Array_Value;
      Files      : constant Value := Self.Memory_Index;
      File_Views : Value := Array_Value;
      procedure Add_Table (Name : String; Rows : Value) is
         Columns : Value := Array_Value;
         Names   : constant Value :=
           (if Length (Rows) = 0
            then Array_Value
            else Member_Names (Element (Rows, 1)));
      begin
         for J in 1 .. Length (Names) loop
            Append
              (Columns,
               Make_Object
                 ([("name", Element (Names, J)),
                   ("type", To_JSON_String ("JSON")),
                   ("pk",
                    To_JSON_Boolean (Get_Text (Element (Names, J)) = "id")),
                   ("notNull", To_JSON_Boolean (False)),
                   ("default", Null_Value)]));
         end loop;
         Append
           (Tables,
            Make_Object
              ([("name", To_JSON_String (Name)),
                ("columns", Columns),
                ("count", To_JSON_Integer (Long_Long_Integer (Length (Rows)))),
                ("rows", State.Tail (Rows, 40))]));
      end Add_Table;
      Key_Values : Value := Array_Value;
   begin
      for J in 1 .. Length (Keys) loop
         declare
            Key : constant String := Get_Text (Element (Keys, J));
         begin
            if Key /= "pings" and Key /= "wakeups" then
               Append
                 (Key_Values,
                  Make_Object
                    ([("k", To_JSON_String (Key)),
                      ("v", To_JSON_String (Encode (Get (Data, Key))))]));
            end if;
         end;
      end loop;
      Add_Table ("kv", Key_Values);
      Add_Table ("pings", Items (Self, "pings"));
      Add_Table ("wakeups", Items (Self, "wakeups"));
      for J in 1 .. Length (Files) loop
         declare
            File : Value := Element (Files, J);
         begin
            Put (File, "firstLine", Get (File, "about"));
            Append (File_Views, File);
         end;
      end loop;
      return
        Make_Object
          ([("path", To_JSON_String (Self.Database.File_Path)),
            ("exists", To_JSON_Boolean (True)),
            ("tables", Tables),
            ("files", File_Views),
            ("ref", Get (Self.Snapshot, "ref"))]);
   end Inspection;
end Ambient.Engine;
