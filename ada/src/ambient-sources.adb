with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Fixed;
with GNAT.SHA256;
with Interfaces;
with VSS.Strings;
with Ambient.Support;
with Ambient.Types;

package body Ambient.Sources is
   use JSON, Support, Types;
   use type Ada.Calendar.Time;
   use type VSS.Strings.Virtual_String;
   Sequence : Long_Long_Integer := 0;
   function Signature (Secret, Body_Text : String) return String is
      Context : GNAT.SHA256.Context :=
        GNAT.SHA256.HMAC_Initial_Context (Secret);
   begin
      GNAT.SHA256.Update (Context, Body_Text);
      return
        "sha256=" & GNAT.SHA256.Message_Digest'(GNAT.SHA256.Digest (Context));
   end Signature;
   function Verify_Signature
     (Secret, Body_Text, Header : String) return Boolean
   is
      use Interfaces;
      Difference : Unsigned_8 := 0;
   begin
      declare
         Expected : constant String := Signature (Secret, Body_Text);
      begin
         if Header'Length /= Expected'Length then
            return False;
         end if;
         for J in Expected'Range loop
            Difference :=
              Difference
              or (Unsigned_8 (Character'Pos (Expected (J)))
                  xor Unsigned_8
                        (Character'Pos
                           (Header (Header'First + J - Expected'First))));
         end loop;
      end;
      return Difference = 0;
   end Verify_Signature;
   function From_Webhook
     (Name, Delivery : String; Payload : Value) return Value
   is
      Repository : constant String :=
        Get_Text (Get (Payload, "repository"), "full_name");
      Action     : constant String := Get_Text (Payload, "action");
      Issue      : Value := Get (Payload, "issue");
      Comment    : constant Value := Get (Payload, "comment");
      Workflow   : constant Value := Get (Payload, "workflow_run");
      Event      : Agent_Event;
      User       : Value;
   begin
      Event.Source := "github";
      if Name in "issues" | "pull_request"
        and then Action in "opened" | "edited"
      then
         if Name = "pull_request" then
            Issue := Get (Payload, "pull_request");
         end if;
         if Issue.Is_Empty then
            return Array_Value;
         end if;
         Event.Id :=
           To_Virtual_String
             ((if Action = "opened" then "issue-" else "edit-")
              & Image (Get_Integer (Issue, "id"))
              & (if Action = "edited" then "-" & Delivery else ""));
         Event.Kind :=
           (if Name = "pull_request"
            then PR_Opened
            elsif Action = "opened"
            then Issue_Opened
            else Issue_Edited);
         Event.Subject :=
           To_Virtual_String
             (Repository & "#" & Image (Get_Integer (Issue, "number")));
         Event.Title := To_Virtual_String (Get_Text (Issue, "title"));
         Event.Body_Text := To_Virtual_String (Get_Text (Issue, "body"));
         Event.URL := To_Virtual_String (Get_Text (Issue, "html_url"));
         User := Get (Issue, "user");
      elsif Name = "issue_comment"
        and Action = "created"
        and not Comment.Is_Empty
        and not Issue.Is_Empty
      then
         Event.Id :=
           To_Virtual_String
             ("comment-" & Image (Get_Integer (Comment, "id")));
         Event.Kind :=
           (if Get (Issue, "pull_request").Is_Empty
            then Issue_Comment
            else PR_Comment);
         Event.Subject :=
           To_Virtual_String
             (Repository & "#" & Image (Get_Integer (Issue, "number")));
         Event.Body_Text := To_Virtual_String (Get_Text (Comment, "body"));
         Event.Title := Event.Body_Text;
         Event.URL := To_Virtual_String (Get_Text (Comment, "html_url"));
         User := Get (Comment, "user");
      elsif Name = "workflow_run"
        and Action = "completed"
        and Get_Text (Workflow, "conclusion") in "failure" | "success"
      then
         Event.Id :=
           To_Virtual_String ("run-" & Image (Get_Integer (Workflow, "id")));
         Event.Kind :=
           (if Get_Text (Workflow, "conclusion") = "failure"
            then CI_Failed
            else CI_Passed);
         Event.Subject :=
           To_Virtual_String ("ci:" & Get_Text (Workflow, "head_branch"));
         Event.Title :=
           To_Virtual_String
             (Get_Text (Workflow, "name")
              & " "
              & Get_Text (Workflow, "conclusion")
              & " on "
              & Get_Text (Workflow, "head_branch"));
         Event.URL := To_Virtual_String (Get_Text (Workflow, "html_url"));
         Event.Login := "github-actions";
      else
         return Array_Value;
      end if;
      if not User.Is_Empty then
         Event.Login := To_Virtual_String (Get_Text (User, "login"));
         Event.Bot :=
           Get_Text (User, "type") = "Bot"
           or Contains (To_UTF_8_String (Event.Login), "[bot]");
      end if;
      Event.Routing := Signal_Of (Event);
      return Make_Array ([Types.Encode (Event)]);
   end From_Webhook;
   function Scenario
     (Name : String; Title : String := ""; Body_Text : String := "")
      return Value
   is
      Event  : Agent_Event;
      Result : Value := Array_Value;
   begin
      Sequence := Sequence + 1;
      Event.Id :=
        To_Virtual_String
          ("scenario-"
           & Image
               (Long_Long_Integer
                  (Long_Float
                     (Ada.Calendar.Clock - Ada.Calendar.Time_Of (1970, 1, 1))
                   * 1000.0))
           & "-"
           & Image (Sequence));
      Event.Source := "sim";
      Event.Subject :=
        To_Virtual_String ("demo/app#" & Image (100 + Sequence));
      Event.Login := "audience";
      Event.Title :=
        To_Virtual_String
          (if Title = "" then "Crash on empty config file" else Title);
      Event.Body_Text := To_Virtual_String (Body_Text);
      if Name = "ci-failed" then
         Event.Kind := CI_Failed;
         Event.Subject := "ci:main";
         Event.Login := "github-actions";
         Event.Title := "CI failed on main: test (inbox.test.adb)";
      elsif Name = "bot-comment" then
         Event.Kind := Issue_Comment;
         Event.Login := "welcome-bot[bot]";
         Event.Bot := True;
         Event.Title := "Thanks for opening your first issue!";
      elsif Name = "dependabot-pr" then
         Event.Kind := PR_Opened;
         Event.Login := "dependabot[bot]";
         Event.Bot := True;
         Event.Title := "Bump dependency";
      elsif Name = "issue-edits" then
         Event.Kind := Issue_Edited;
      elsif Name = "self-echo" then
         Event.Kind := Issue_Comment;
         Event.Login := "ambient-agent";
         Event.Body_Text := To_Virtual_String (Self_Marker);
      elsif Name = "reaction" then
         Event.Kind := Issue_Comment;
         Event.Body_Text := "+1";
         Event.Title := "+1";
      elsif Name in "pr-opened" | "cat-pr" then
         Event.Kind := PR_Opened;
         Event.Title :=
           To_Virtual_String
             (if Name = "cat-pr"
              then "Cat mode: a walking cat spinner"
              else "Add retry to the GitHub poller");
      elsif Name /= "new-issue" then
         raise Constraint_Error with "unknown scenario: " & Name;
      end if;
      Event.Routing := Signal_Of (Event);
      Append (Result, Types.Encode (Event));
      if Name = "issue-edits" then
         for J in 2 .. 3 loop
            Event.Id := Event.Id & To_Virtual_String ("-" & Trim (J'Image));
            Append (Result, Types.Encode (Event));
         end loop;
      end if;
      return Result;
   end Scenario;
   procedure Initialize (Self : in out GitHub_Poller; Path : String) is
   begin
      Self.Database.Open (Path);
      Self.Bootstrapped := Get_Boolean (Self.Database.Get ("bootstrapped"));
   end Initialize;
   procedure Poll (Self : in out GitHub_Poller; Agent : in out Engine.Agent) is
      Repository : constant String := Environment ("GITHUB_REPO");
      Seen       : Value := Self.Database.Get ("seen");
      Fresh      : Value := Array_Value;
      procedure Track (Events : Value) is
      begin
         for J in 1 .. Length (Events) loop
            declare
               Event : constant Value := Element (Events, J);
               Id    : constant String := Get_Text (Event, "id");
            begin
               if not Get_Boolean (Seen, Id) then
                  Append (Fresh, Event);
                  Put (Seen, Id, To_JSON_Boolean (True));
               end if;
            end;
         end loop;
      end Track;
      function Payload (Key : String; Item : Value) return Value is
      begin
         return
           Make_Object
             ([("repository",
                Make_Object ([("full_name", To_JSON_String (Repository))])),
               ("action",
                To_JSON_String
                  (if Key = "workflow_run" then "completed" else "opened")),
               (To_Virtual_String (Key), Item)]);
      end Payload;
   begin
      if Repository = "" then
         return;
      end if;
      declare
         Issues   : constant Value :=
           Parse
             (Run
                ("gh",
                 ["api",
                  To_Virtual_String
                    ("repos/"
                     & Repository
                     & "/issues?state=all&sort=created&direction=desc&per_page=30")]));
         Comments : constant Value :=
           Parse
             (Run
                ("gh",
                 ["api",
                  To_Virtual_String
                    ("repos/"
                     & Repository
                     & "/issues/comments?sort=created&direction=desc&per_page=30")]));
         Runs     : constant Value :=
           Get
             (Parse
                (Run
                   ("gh",
                    ["api",
                     To_Virtual_String
                       ("repos/"
                        & Repository
                        & "/actions/runs?per_page=10&status=completed")])),
              "workflow_runs");
      begin
         for J in 1 .. Length (Issues) loop
            declare
               Issue : constant Value := Element (Issues, J);
               Is_PR : constant Boolean :=
                 not Get (Issue, "pull_request").Is_Empty;
            begin
               Track
                 (From_Webhook
                    ((if Is_PR then "pull_request" else "issues"),
                     "poll",
                     Payload
                       ((if Is_PR then "pull_request" else "issue"), Issue)));
            end;
         end loop;
         for J in 1 .. Length (Comments) loop
            declare
               Comment   : constant Value := Element (Comments, J);
               Issue_URL : constant String := Get_Text (Comment, "issue_url");
               Slash     : constant Natural :=
                 Ada.Strings.Fixed.Index
                   (Issue_URL, "/", Ada.Strings.Backward);
               Issue     : Value :=
                 Make_Object
                   ([("number",
                      To_JSON_Integer
                        (Long_Long_Integer'Value
                           (Issue_URL (Slash + 1 .. Issue_URL'Last))))]);
               Item      : Value := Payload ("comment", Comment);
            begin
               if Contains (Get_Text (Comment, "html_url"), "/pull/") then
                  Put (Issue, "pull_request", Object_Value);
               end if;
               Put (Item, "action", To_JSON_String ("created"));
               Put (Item, "issue", Issue);
               Track (From_Webhook ("issue_comment", "poll", Item));
            end;
         end loop;
         for J in 1 .. Length (Runs) loop
            Track
              (From_Webhook
                 ("workflow_run",
                  "poll",
                  Payload ("workflow_run", Element (Runs, J))));
         end loop;
      end;
      if Self.Bootstrapped then
         Agent.Replay (Fresh);
      end if;
      Self.Bootstrapped := True;
      Self.Database.Set ("seen", Seen);
      Self.Database.Set ("bootstrapped", To_JSON_Boolean (True));
      Self.Database.Save;
   exception
      when Error : others =>
         Log
           ("GitHub poll failed: " & Ada.Exceptions.Exception_Message (Error));
   end Poll;
end Ambient.Sources;
