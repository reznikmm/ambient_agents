with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with GNAT.Sockets;
with GNAT.OS_Lib;
with Ambient.JSON;
with Ambient.Decisions;
with Ambient.Sources;
with Ambient.Shutdown;
with Ambient.Support;
with VSS.Strings;

package body Ambient.Server is
   use JSON, Support, GNAT.Sockets;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Calendar.Time;
   CRLF  : constant String := ASCII.CR & ASCII.LF;
   Limit : constant := 1_048_576;
   function URL_Decode (Text : String) return String is
      Result   : String (1 .. Text'Length);
      Last     : Natural := 0;
      Position : Positive := Text'First;
   begin
      while Position <= Text'Last loop
         Last := Last + 1;
         if Text (Position) = '%' and Position + 2 <= Text'Last then
            Result (Last) :=
              Character'Val
                (Integer'Value
                   ("16#" & Text (Position + 1 .. Position + 2) & "#"));
            Position := Position + 3;
         else
            Result (Last) :=
              (if Text (Position) = '+' then ' ' else Text (Position));
            Position := Position + 1;
         end if;
      end loop;
      return Result (1 .. Last);
   end URL_Decode;
   function Header (Headers, Name : String) return String is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Headers);
      Start : constant Natural :=
        Ada.Strings.Fixed.Index (Lower, CRLF & Name & ":");
      Last  : Natural;
   begin
      if Start = 0 then
         return "";
      end if;
      Last := Ada.Strings.Fixed.Index (Headers, CRLF, Start + 2);
      return Trim (Headers (Start + 3 + Name'Length .. Last - 1));
   end Header;
   procedure Send (Socket : Socket_Type; Text : String) is
      Data  : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
      Last  : Ada.Streams.Stream_Element_Offset;
      Start : Ada.Streams.Stream_Element_Offset := 1;
   begin
      for J in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (J - Text'First + 1)) :=
           Character'Pos (Text (J));
      end loop;
      while Start <= Data'Last loop
         Send_Socket (Socket, Data (Start .. Data'Last), Last);
         if Last < Start then
            raise Socket_Error with "connection closed while writing";
         end if;
         Start := Last + 1;
      end loop;
   end Send;
   procedure Respond
     (Socket       : Socket_Type;
      Status       : Natural;
      Text         : String;
      Content_Type : String := "application/json")
   is
      Reason : constant String :=
        (case Status is
           when 200    => "OK",
           when 202    => "Accepted",
           when 204    => "No Content",
           when 400    => "Bad Request",
           when 401    => "Unauthorized",
           when 404    => "Not Found",
           when 413    => "Payload Too Large",
           when 501    => "Not Implemented",
           when others => "Server Error");
   begin
      Send
        (Socket,
         "HTTP/1.1 "
         & Trim (Status'Image)
         & " "
         & Reason
         & CRLF
         & "Content-Type: "
         & Content_Type
         & CRLF
         & "Content-Length: "
         & Trim (Text'Length'Image)
         & CRLF
         & "Access-Control-Allow-Origin: *"
         & CRLF
         & "Access-Control-Allow-Headers: content-type"
         & CRLF
         & "Access-Control-Allow-Methods: GET, POST, OPTIONS"
         & CRLF
         & "Connection: close"
         & CRLF
         & CRLF
         & Text);
   end Respond;
   procedure Receive_Request
     (Socket             : Socket_Type;
      Headers, Body_Text : out VSS.Strings.Virtual_String)
   is
      Data       : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last       : Ada.Streams.Stream_Element_Offset;
      Raw        : Ada.Strings.Unbounded.Unbounded_String;
      Header_End : Natural := 0;
      Size       : Natural := 0;
   begin
      loop
         Receive_Socket (Socket, Data, Last);
         if Last < Data'First then
            raise Constraint_Error with "truncated HTTP request";
         end if;
         declare
            Chunk : String (1 .. Integer (Last));
         begin
            for J in Chunk'Range loop
               Chunk (J) :=
                 Character'Val (Data (Ada.Streams.Stream_Element_Offset (J)));
            end loop;
            Ada.Strings.Unbounded.Append (Raw, Chunk);
         end;
         declare
            Text : constant String := Ada.Strings.Unbounded.To_String (Raw);
         begin
            if Text'Length > Limit + 16_384 then
               raise Constraint_Error with "HTTP request exceeds 1 MiB";
            end if;
            if Header_End = 0 then
               Header_End := Ada.Strings.Fixed.Index (Text, CRLF & CRLF);
               if Header_End > 0 then
                  Headers := To_Virtual_String (Text (1 .. Header_End + 1));
                  if Header (To_UTF_8_String (Headers), "transfer-encoding")
                    /= ""
                  then
                     raise Constraint_Error
                       with
                         "chunked requests are not supported; send Content-Length";
                  end if;
                  declare
                     Length_Text : constant String :=
                       Header (To_UTF_8_String (Headers), "content-length");
                  begin
                     Size :=
                       (if Length_Text = ""
                        then 0
                        else Natural'Value (Length_Text));
                  end;
                  if Size > Limit then
                     raise Constraint_Error with "HTTP body exceeds 1 MiB";
                  end if;
               elsif Text'Length > 16_384 then
                  raise Constraint_Error with "HTTP headers exceed 16 KiB";
               end if;
            end if;
            if Header_End > 0 and then Text'Length >= Header_End + 3 + Size
            then
               Body_Text :=
                 To_Virtual_String
                   (Text (Header_End + 4 .. Header_End + 3 + Size));
               return;
            end if;
         end;
      end loop;
   end Receive_Request;
   procedure Run
     (Agent     : in out Engine.Agent;
      Port      : Positive;
      Dashboard : Boolean := False)
   is
      Listener, Connection : Socket_Type := No_Socket;
      Address              : Sock_Addr_Type;
      Selector             : Selector_Type;
      Reads, Writes        : Socket_Set_Type;
      Status               : Selector_Status;
      package Socket_Vectors is new
        Ada.Containers.Vectors (Positive, Socket_Type);
      Subscribers          : Socket_Vectors.Vector;
      Poller               : Sources.GitHub_Poller;
      Last_Poll            : Ada.Calendar.Time := Ada.Calendar.Clock - 21.0;
      Last_Tick            : Ada.Calendar.Time := Ada.Calendar.Clock;
      Last_Flush           : Ada.Calendar.Time := Ada.Calendar.Clock;
      Selector_Ready       : Boolean := False;
      Registered           : Boolean := False;
      Scheduled            : Value := Array_Value;
      Registry_Path        : constant String :=
        Environment
          ("REGISTRY_PATH", Environment ("HOME") & "/.ambient-workshop/ada");
      function Instances return Value is
         Search     : Ada.Directories.Search_Type;
         Entry_Item : Ada.Directories.Directory_Entry_Type;
         Result     : Value := Array_Value;
      begin
         if Ada.Directories.Exists (Registry_Path) then
            Ada.Directories.Start_Search (Search, Registry_Path, "*.json");
            while Ada.Directories.More_Entries (Search) loop
               Ada.Directories.Get_Next_Entry (Search, Entry_Item);
               declare
                  Item       : constant Value :=
                    Parse (Read_File (Ada.Directories.Full_Name (Entry_Item)));
                  Process_Id : constant Long_Long_Integer :=
                    Get_Integer (Item, "pid");
                  function Kill (Pid, Signal : Integer) return Integer
                  with Import, Convention => C, External_Name => "kill";
               begin
                  if Process_Id > 0 and then Kill (Integer (Process_Id), 0) = 0
                  then
                     Append (Result, Item);
                  end if;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
         end if;
         return Result;
      end Instances;
      function Target (Name : String) return Value is
         All_Instances : constant Value := Instances;
      begin
         for J in 1 .. Length (All_Instances) loop
            if Get_Text (Element (All_Instances, J), "name") = Name then
               return Element (All_Instances, J);
            end if;
         end loop;
         raise Constraint_Error with "no running instance " & Name;
      end Target;
      function Forward (Name, Path : String; Data : Value) return Value is
         Instance : constant Value := Target (Name);
         URL      : constant String :=
           "http://127.0.0.1:" & Image (Get_Integer (Instance, "port")) & Path;
      begin
         if Get_Integer (Instance, "port") = Long_Long_Integer (Port) then
            if Path = "/api/inspection" then
               return Agent.Inspection;
            else
               raise Constraint_Error
                 with "use the instance's direct API for this operation";
            end if;
         end if;
         return
           Parse
             (Run
                ("curl",
                 ["--silent",
                  "--show-error",
                  "--fail",
                  "--max-time",
                  "30",
                  "--header",
                  "Content-Type: application/json",
                  "--data-binary",
                  "@-",
                  To_Virtual_String (URL)],
                 Encode (Data),
                 Timeout => 35));
      end Forward;
      procedure Route
        (Socket                          : Socket_Type;
         Method, URI, Headers, Body_Text : String;
         Keep_Open                       : out Boolean)
      is
         Query_Start : constant Natural := Ada.Strings.Fixed.Index (URI, "?");
         Path        : constant String :=
           (if Query_Start = 0
            then URI
            else URI (URI'First .. Query_Start - 1));
         Data        : constant Value :=
           (if Body_Text = "" then Object_Value else Parse (Body_Text));
         function Query (Key : String) return String is
            Prefix : constant String := Key & "=";
            Start  : Natural :=
              (if Query_Start = 0 then 0 else Query_Start + 1);
            Last   : Natural;
         begin
            while Start > 0 and Start <= URI'Last loop
               Last := Ada.Strings.Fixed.Index (URI, "&", Start);
               if Last = 0 then
                  Last := URI'Last + 1;
               end if;
               if Last - Start >= Prefix'Length
                 and then URI (Start .. Start + Prefix'Length - 1) = Prefix
               then
                  return URL_Decode (URI (Start + Prefix'Length .. Last - 1));
               end if;
               Start := Last + 1;
            end loop;
            return "";
         end Query;
         procedure Reply (Item : Value; Code : Natural := 200) is
         begin
            Respond (Socket, Code, Encode (Item));
         end Reply;
         function Instance_Name return String
         is (if Get_Text (Data, "instance") = ""
             then "stage"
             else Get_Text (Data, "instance"));
      begin
         Keep_Open := False;
         if Method = "OPTIONS" then
            Respond (Socket, 204, "");
         elsif Method = "GET" and Path = "/api/stream" then
            Send
              (Socket,
               "HTTP/1.1 200 OK"
               & CRLF
               & "Content-Type: text/event-stream"
               & CRLF
               & "Access-Control-Allow-Origin: *"
               & CRLF
               & "Cache-Control: no-cache"
               & CRLF
               & "Connection: keep-alive"
               & CRLF
               & CRLF
               & "data: "
               & Encode
                   (Make_Object
                      ([("t", To_JSON_String ("snapshot")),
                        ("state", Agent.Snapshot)]))
               & ASCII.LF
               & ASCII.LF);
            Subscribers.Append (Socket);
            Keep_Open := True;
         elsif Method = "GET" and Path = "/api/state" then
            Reply (Agent.Snapshot);
         elsif Method in "GET" | "POST" and Path = "/api/inspection" then
            Reply (Agent.Inspection);
         elsif Method = "GET" and Path = "/api/db" then
            Reply
              (Forward
                 ((if Query ("instance") = ""
                   then "stage"
                   else Query ("instance")),
                  "/api/inspection",
                  Object_Value));
         elsif Method = "GET" and Path = "/api/decide/providers" then
            Reply (Decisions.Providers);
         elsif Method = "GET" and Path = "/api/decide/presets" then
            Reply (Decisions.Presets);
         elsif Method = "GET" and Path = "/api/decide/lanes" then
            Reply (Decisions.Lanes);
         elsif Method = "GET" and Path = "/api/decide/prices" then
            Reply
              (Make_Object
                 ([("model",
                    To_JSON_String
                      (Environment ("GATE_MODEL", "local-model"))),
                   ("llm", Null_Value),
                   ("input",
                    Make_Object
                      ([("clef", To_JSON_Number (0.24 / 1_000_000.0)),
                        ("clef-flash",
                         To_JSON_Number (0.038 / 1_000_000.0))]))]));
         elsif Method = "POST" and Path = "/api/decide" then
            Reply
              (Decisions.Decide
                 (Get_Text (Data, "provider"),
                  Get (Data, "state"),
                  Get (Data, "questions")));
         elsif Method = "POST" and Path = "/api/decide/race" then
            Respond
              (Socket,
               200,
               Decisions.Race (Get_Text (Data, "lane"), Get (Data, "states")),
               "application/x-ndjson");
         elsif Method = "GET" and Path = "/api/thread" then
            Reply (Make_Object ([("entries", Agent.Thread)]));
         elsif Method = "GET" and Path = "/chat" then
            declare
               Instance : constant Value :=
                 Target
                   ((if Query ("instance") = ""
                     then "stage"
                     else Query ("instance")));
               Location : constant String :=
                 "http://127.0.0.1:"
                 & Image (Get_Integer (Instance, "port"))
                 & "/"
                 & (if Query ("embed") /= "" then "?embed=1" else "");
            begin
               Send
                 (Socket,
                  "HTTP/1.1 302 Found"
                  & CRLF
                  & "Location: "
                  & Location
                  & CRLF
                  & "Content-Length: 0"
                  & CRLF
                  & "Connection: close"
                  & CRLF
                  & CRLF);
            end;
         elsif Path = "/api/watches" and Method in "GET" | "POST" then
            if Method = "POST" then
               if Is_String (Get (Data, "add")) then
                  Agent.Watch (Get_Text (Data, "add"));
               end if;
               if Is_String (Get (Data, "remove")) then
                  Agent.Watch (Get_Text (Data, "remove"), Remove => True);
               end if;
            end if;
            Reply (Make_Object ([("watches", Agent.Watches)]));
         elsif Method = "GET" and Path = "/api/memory" then
            Reply
              (Make_Object
                 ([("where",
                    To_JSON_String (Environment ("MEMORY_DIR", "memory"))),
                   ("files", Agent.Memory_Index)]));
         elsif Method = "GET" and Path = "/api/memory/file" then
            Reply
              (Make_Object
                 ([("text",
                    To_JSON_String (Agent.Memory_Read (Query ("path"))))]));
         elsif Method = "GET" and Path = "/api/wakeups" then
            Reply (Agent.Pending_Wakeups);
         elsif Method = "POST" and Path = "/api/chat" then
            if Trim (Get_Text (Data, "message")) = "" then
               raise Constraint_Error with "message required";
            end if;
            Respond
              (Socket,
               200,
               Agent.Chat (Get_Text (Data, "message")),
               "application/x-ndjson");
         elsif Method = "POST" and Path = "/api/trigger" then
            declare
               Events : constant Value :=
                 Sources.Scenario
                   (Get_Text (Data, "scenario"),
                    Get_Text (Data, "title"),
                    Get_Text (Data, "body"));
            begin
               Agent.Replay (Events);
               Reply
                 (Make_Object
                    ([("injected",
                       To_JSON_Integer
                         (Long_Long_Integer (Length (Events))))]));
            end;
         elsif Method = "POST" and Path = "/api/storm" then
            declare
               Events             : constant Value :=
                 Parse (Read_File ("fixtures/storm.json"));
               Delay_Milliseconds : constant Long_Long_Integer :=
                 Get_Integer (Data, "rateMs", 160);
               Start              : constant Long_Long_Integer :=
                 Long_Long_Integer
                   (Long_Float
                      (Ada.Calendar.Clock
                       - Ada.Calendar.Formatting.Time_Of (1970, 1, 1))
                    * 1000.0);
            begin
               if Delay_Milliseconds not in 0 .. 60_000 then
                  raise Constraint_Error with "rateMs must be 0..60000";
               end if;
               for J in 1 .. Length (Events) loop
                  Append
                    (Scheduled,
                     Make_Object
                       ([("at",
                          To_JSON_Integer
                            (Start
                             + Long_Long_Integer (J - 1)
                               * Delay_Milliseconds)),
                         ("event", Element (Events, J))]));
               end loop;
               Reply
                 (Make_Object
                    ([("events",
                       To_JSON_Integer (Long_Long_Integer (Length (Events)))),
                      ("seconds",
                       To_JSON_Number
                         (Long_Float (Length (Events))
                          * Long_Float (Delay_Milliseconds)
                          / 1000.0))]));
            end;
         elsif Method = "POST" and Path = "/api/replay" then
            declare
               Events : constant Value :=
                 Parse
                   (Read_File
                      (Inside
                         (Ada.Directories.Current_Directory,
                          Get_Text (Data, "file"))));
            begin
               Agent.Replay (Events, Unique => True);
               Reply
                 (Make_Object
                    ([("injected",
                       To_JSON_Integer
                         (Long_Long_Integer (Length (Events))))]));
            end;
         elsif Method = "POST" and Path = "/api/clock" then
            if not Get (Data, "advanceMinutes").Is_Empty then
               Agent.Advance
                 (Long_Long_Integer (Get_Number (Data, "advanceMinutes")));
            end if;
            if Is_String (Get (Data, "jumpTo")) then
               Agent.Jump_To (Get_Text (Data, "jumpTo"));
               Agent.Tick;
            end if;
            Reply (Make_Object ([("clock", To_JSON_Integer (Agent.Now))]));
         elsif Method = "POST" and Path = "/api/digest" then
            Reply
              (Make_Object
                 ([("items",
                    To_JSON_Integer (Long_Long_Integer (Agent.Digest)))]));
         elsif Method = "POST" and Path = "/api/answer" then
            if not Is_Integer (Get (Data, "id"))
              or not Is_Boolean (Get (Data, "yes"))
            then
               raise Constraint_Error with "id and yes required";
            end if;
            if Agent.Ask_Answer
                 (Get_Integer (Data, "id"), Get_Boolean (Data, "yes"))
            then
               Reply (Make_Object ([("ok", To_JSON_Boolean (True))]));
            else
               Reply
                 (Make_Object
                    ([("error", To_JSON_String ("no open ask with that id"))]),
                  404);
            end if;
         elsif Method = "POST" and Path = "/api/reset" then
            Agent.Reset;
            Scheduled := Array_Value;
            Reply (Make_Object ([("ok", To_JSON_Boolean (True))]));
         elsif Method = "POST" and Path = "/api/step" then
            Agent.Set_Step (Natural (Get_Integer (Data, "step")));
            Scheduled := Array_Value;
            if Registered then
               declare
                  Path : constant String :=
                    Registry_Path & "/" & Trim (Port'Image) & ".json";
                  Item : Value := Parse (Read_File (Path));
               begin
                  Put (Item, "ref", Get (Agent.Snapshot, "ref"));
                  Write_File (Path, Encode (Item));
               end;
            end if;
            Reply (Agent.Snapshot);
         elsif Method = "POST" and Path = "/webhooks/github" then
            if Environment ("GITHUB_WEBHOOK_SECRET") /= ""
              and then not Sources.Verify_Signature
                             (Environment ("GITHUB_WEBHOOK_SECRET"),
                              Body_Text,
                              Header (Headers, "x-hub-signature-256"))
            then
               Reply
                 (Make_Object ([("error", To_JSON_String ("bad signature"))]),
                  401);
            elsif Header (Headers, "x-github-event") = "ping" then
               Reply (Make_Object ([("ok", To_JSON_Boolean (True))]));
            else
               declare
                  Events : constant Value :=
                    Sources.From_Webhook
                      (Header (Headers, "x-github-event"),
                       Header (Headers, "x-github-delivery"),
                       Data);
               begin
                  Agent.Replay (Events);
                  Reply
                    (Make_Object
                       ([("events",
                          To_JSON_Integer
                            (Long_Long_Integer (Length (Events))))]),
                     202);
               end;
            end if;
         elsif Method = "GET" and Path = "/api/instances" then
            Reply (Instances);
         elsif Method = "POST" and Path = "/api/webhook" then
            declare
               Sample     : constant String := Get_Text (Data, "sample");
               Instance   : constant Value := Target (Instance_Name);
               Identifier : constant Long_Long_Integer := Agent.Now;
               Issue      : constant Value :=
                 Make_Object
                   ([("id", To_JSON_Integer (Identifier)),
                     ("number", To_JSON_Integer (Identifier mod 1000 + 1)),
                     ("title",
                      To_JSON_String
                        ("Cats are missing from the welcome page")),
                     ("body", To_JSON_String ("Where is the cat?")),
                     ("user",
                      Make_Object
                        ([("login", To_JSON_String ("maria")),
                          ("type", To_JSON_String ("User"))]))]);
               Payload    : Value :=
                 Make_Object
                   ([("repository",
                      Make_Object
                        ([("full_name", To_JSON_String ("demo/app"))]))]);
               Event_Name : constant String :=
                 (if Sample = "ci"
                  then "workflow_run"
                  elsif Sample = "comment"
                  then "issue_comment"
                  elsif Sample = "pr"
                  then "pull_request"
                  else "issues");
            begin
               if Sample not in "issue" | "pr" | "comment" | "ci" then
                  raise Constraint_Error
                    with "sample must be issue, pr, comment or ci";
               elsif Sample = "ci" then
                  Put (Payload, "action", To_JSON_String ("completed"));
                  Put
                    (Payload,
                     "workflow_run",
                     Make_Object
                       ([("id", To_JSON_Integer (Identifier)),
                         ("name", To_JSON_String ("CI")),
                         ("head_branch", To_JSON_String ("main")),
                         ("conclusion", To_JSON_String ("failure"))]));
               elsif Sample = "comment" then
                  Put (Payload, "action", To_JSON_String ("created"));
                  Put (Payload, "issue", Issue);
                  Put
                    (Payload,
                     "comment",
                     Make_Object
                       ([("id", To_JSON_Integer (Identifier)),
                         ("body", To_JSON_String ("Is there a workaround?")),
                         ("user", Get (Issue, "user"))]));
               else
                  Put (Payload, "action", To_JSON_String ("opened"));
                  Put
                    (Payload,
                     (if Sample = "pr" then "pull_request" else "issue"),
                     Issue);
               end if;
               declare
                  Body_Text : constant String := Encode (Payload);
                  URL       : constant String :=
                    "http://127.0.0.1:"
                    & Image (Get_Integer (Instance, "port"))
                    & "/webhooks/github";
                  Response  : constant String :=
                    Run
                      ("curl",
                       ["--silent",
                        "--show-error",
                        "--max-time",
                        "10",
                        "--header",
                        "Content-Type: application/json",
                        "--header",
                        To_Virtual_String ("X-GitHub-Event: " & Event_Name),
                        "--header",
                        To_Virtual_String
                          ("X-Hub-Signature-256: "
                           & Sources.Signature
                               ((if Get_Boolean (Data, "forged")
                                 then "not-the-secret"
                                 else Environment ("GITHUB_WEBHOOK_SECRET")),
                                Body_Text)),
                        "--data-binary",
                        "@-",
                        "--write-out",
                        To_Virtual_String (ASCII.LF & "%{http_code}"),
                        To_Virtual_String (URL)],
                       Body_Text);
                  Split     : constant Natural :=
                    Ada.Strings.Fixed.Index
                      (Response, String'(1 => ASCII.LF), Ada.Strings.Backward);
               begin
                  Reply
                    (Make_Object
                       ([("status",
                          To_JSON_Integer
                            (Long_Long_Integer'Value
                               (Response (Split + 1 .. Response'Last)))),
                         ("event", To_JSON_String (Event_Name)),
                         ("response",
                          To_JSON_String
                            (Response (Response'First .. Split - 1)))]));
               end;
            end;
         elsif Method = "GET" and Path = "/api/summary" then
            Reply (Make_Object ([("instances", Instances)]));
         elsif Method = "GET" and Path = "/api/pattern" then
            Reply (Parse (Read_File ("dj/pattern.json", "{}")));
         elsif Method = "GET" and Path = "/api/stage" then
            declare
               Instance : constant Value := Target ("stage");
            begin
               Reply
                 (Make_Object
                    ([("exists", To_JSON_Boolean (True)),
                      ("running", To_JSON_Boolean (True)),
                      ("port", Get (Instance, "port")),
                      ("ref", Get (Instance, "ref"))]));
            end;
         elsif Method = "POST" and Path = "/api/stage/load" then
            declare
               State : constant Value := Forward ("stage", "/api/step", Data);
            begin
               Reply
                 (Make_Object
                    ([("port", Get (State, "port")),
                      ("ref", Get (State, "ref"))]));
            end;
         elsif Method = "GET" and Path = "/api/stage/prompt" then
            declare
               Step : constant Natural := Natural'Value (Query ("step"));
            begin
               if Step > 8 then
                  raise Constraint_Error with "step must be 0..8";
               end if;
               Reply
                 (Make_Object
                    ([("text",
                       To_JSON_String
                         (Read_File
                            ("ada/prompts/step-"
                             & Trim (Step'Image)
                             & ".md")))]));
            end;
         elsif Method = "POST" and Path = "/api/stage/eval" then
            declare
               Step : constant String :=
                 Get_Text (Target (Instance_Name), "ref");
            begin
               Reply
                 (Parse
                    (Run
                       ("ada/bin/ambient_evals",
                        ["--json",
                         "--step",
                         To_Virtual_String (Step (Step'Last .. Step'Last))],
                        Timeout => 30)));
            end;
         elsif Method = "POST" and Path = "/api/stage/preference" then
            Reply (Forward (Instance_Name, "/api/preference", Data));
         elsif Method = "POST" and Path = "/api/preference" then
            Append_File
              (Inside (Environment ("MEMORY_DIR", "memory"), "preferences.md"),
               ASCII.LF & Get_Text (Data, "text") & ASCII.LF);
            Reply
              (Make_Object
                 ([("preferences",
                    To_JSON_String
                      (Read_File
                         (Environment ("MEMORY_DIR", "memory")
                          & "/preferences.md")))]));
         elsif Path = "/api/stage/scores" and Method in "POST" | "GET" then
            declare
               Scores : Value :=
                 Parse (Read_File (".data/stage-scores.json", "{}"));
            begin
               if Get_Boolean (Data, "clear") then
                  Scores := Object_Value;
               elsif Get_Text (Data, "ref") /= "" then
                  Put (Scores, Get_Text (Data, "ref"), Get (Data, "stats"));
               end if;
               if Method = "POST" then
                  Write_File (".data/stage-scores.json", Encode (Scores));
               end if;
               Reply (Scores);
            end;
         elsif Method = "GET" and (Path = "/" or Path = "/index.html") then
            Respond
              (Socket,
               200,
               Read_File
                 (if Dashboard then "ada/app/home.html" else "app/index.html"),
               "text/html; charset=utf-8");
         elsif Method = "GET"
           and Path
               in "/stage"
                | "/presenter"
                | "/dashboard"
                | "/decisions"
                | "/db"
                | "/stage-chapters.js"
         then
            declare
               File : constant String :=
                 (if Path = "/dashboard"
                  then "agents.html"
                  elsif Path = "/stage-chapters.js"
                  then "stage-chapters.js"
                  else Path (Path'First + 1 .. Path'Last) & ".html");
            begin
               Respond
                 (Socket,
                  200,
                  Read_File
                    ((if File = "stage-chapters.js"
                      then "ada/app/"
                      else "dashboard/")
                     & File),
                  (if Contains (File, ".js")
                   then "text/javascript"
                   else "text/html; charset=utf-8"));
            end;
         else
            Reply
              (Make_Object ([("error", To_JSON_String ("not found"))]), 404);
         end if;
      end Route;
      procedure Broadcast is
         Updates : constant Value := Agent.Updates;
      begin
         for Index in reverse Subscribers.First_Index .. Subscribers.Last_Index
         loop
            begin
               for J in 1 .. Length (Updates) loop
                  Send
                    (Subscribers (Index),
                     "data: "
                     & Encode (Element (Updates, J))
                     & ASCII.LF
                     & ASCII.LF);
               end loop;
            exception
               when Error : Socket_Error =>
                  Log
                    ("event stream closed: "
                     & Ada.Exceptions.Exception_Message (Error));
                  Close_Socket (Subscribers (Index));
                  Subscribers.Delete (Index);
            end;
         end loop;
         Agent.Clear_Updates;
      end Broadcast;
      procedure Finish is
         Deleted : Boolean;
      begin
         if Connection /= No_Socket then
            Close_Socket (Connection);
            Connection := No_Socket;
         end if;
         for Socket of Subscribers loop
            Close_Socket (Socket);
         end loop;
         Subscribers.Clear;
         if Listener /= No_Socket then
            Close_Socket (Listener);
            Listener := No_Socket;
         end if;
         if Selector_Ready then
            Close_Selector (Selector);
            Selector_Ready := False;
         end if;
         if Registered then
            GNAT.OS_Lib.Delete_File
              (Registry_Path & "/" & Trim (Port'Image) & ".json", Deleted);
            if not Deleted then
               Log
                 ("cannot remove registry entry for port "
                  & Trim (Port'Image));
            end if;
            Registered := False;
         end if;
      end Finish;
   begin
      Ambient.Shutdown.Install;
      Create_Socket (Listener);
      Set_Socket_Option (Listener, Socket_Level, (Reuse_Address, True));
      Bind_Socket
        (Listener,
         (Family => Family_Inet,
          Addr   => Inet_Addr ("127.0.0.1"),
          Port   => Port_Type (Port)));
      Listen_Socket (Listener);
      Create_Selector (Selector);
      Selector_Ready := True;
      Poller.Initialize
        (Environment ("STATE_PATH", ".data/agent.json") & ".github");
      if not Dashboard then
         declare
            Process_Id : constant String :=
              Trim
                (Integer'Image
                   (GNAT.OS_Lib.Pid_To_Integer
                      (GNAT.OS_Lib.Current_Process_Id)));
            State      : constant Value := Agent.Snapshot;
         begin
            Write_File
              (Registry_Path & "/" & Trim (Port'Image) & ".json",
               Encode
                 (Make_Object
                    ([("name", Get (State, "instance")),
                      ("port", To_JSON_Integer (Long_Long_Integer (Port))),
                      ("ref", Get (State, "ref")),
                      ("cwd",
                       To_JSON_String (Ada.Directories.Current_Directory)),
                      ("pid",
                       To_JSON_Integer (Long_Long_Integer'Value (Process_Id))),
                      ("workerMode", Get (State, "workerMode")),
                      ("startedAt", To_JSON_Integer (Agent.Now))])));
         end;
         Registered := True;
      end if;
      Log ("Ada workshop listening on http://127.0.0.1:" & Trim (Port'Image));
      while not Ambient.Shutdown.Requested loop
         Empty (Reads);
         Empty (Writes);
         Set (Reads, Listener);
         Check_Selector (Selector, Reads, Writes, Status, Timeout => 0.1);
         if Status = Completed and then Is_Set (Reads, Listener) then
            Accept_Socket (Listener, Connection, Address);
            Set_Socket_Option
              (Connection, Socket_Level, (Receive_Timeout, Timeout => 5.0));
            Set_Socket_Option
              (Connection, Socket_Level, (Send_Timeout, Timeout => 2.0));
            declare
               Headers, Body_Text : VSS.Strings.Virtual_String;
               Keep_Open          : Boolean := False;
            begin
               begin
                  Receive_Request (Connection, Headers, Body_Text);
                  declare
                     Text    : constant String := To_UTF_8_String (Headers);
                     Space   : constant Natural :=
                       Ada.Strings.Fixed.Index (Text, " ");
                     End_URI : constant Natural :=
                       Ada.Strings.Fixed.Index (Text, " ", Space + 1);
                  begin
                     if Space = 0 or End_URI = 0 then
                        raise Constraint_Error
                          with "invalid HTTP request line";
                     end if;
                     Route
                       (Connection,
                        Text (1 .. Space - 1),
                        Text (Space + 1 .. End_URI - 1),
                        To_UTF_8_String (Headers),
                        To_UTF_8_String (Body_Text),
                        Keep_Open);
                  end;
               exception
                  when Error : Constraint_Error =>
                     Respond
                       (Connection,
                        400,
                        Encode
                          (Make_Object
                             ([("error",
                                To_JSON_String
                                  (Ada.Exceptions.Exception_Message
                                     (Error)))])));
                  when Error : others =>
                     Log
                       ("HTTP request failed: "
                        & Ada.Exceptions.Exception_Message (Error));
                     Respond
                       (Connection,
                        500,
                        Encode
                          (Make_Object
                             ([("error",
                                To_JSON_String
                                  (Ada.Exceptions.Exception_Message
                                     (Error)))])));
               end;
               if not Keep_Open then
                  Close_Socket (Connection);
               end if;
               Connection := No_Socket;
            exception
               when Error : Socket_Error =>
                  Log
                    ("HTTP connection closed: "
                     & Ada.Exceptions.Exception_Message (Error));
                  if Connection /= No_Socket then
                     Close_Socket (Connection);
                     Connection := No_Socket;
                  end if;
            end;
         end if;
         declare
            Remaining : Value := Array_Value;
            Real_Now  : constant Long_Long_Integer :=
              Long_Long_Integer
                (Long_Float
                   (Ada.Calendar.Clock
                    - Ada.Calendar.Formatting.Time_Of (1970, 1, 1))
                 * 1000.0);
         begin
            for J in 1 .. Length (Scheduled) loop
               declare
                  Item : constant Value := Element (Scheduled, J);
               begin
                  if Get_Integer (Item, "at") <= Real_Now then
                     Agent.Replay (Make_Array ([Get (Item, "event")]));
                  else
                     Append (Remaining, Item);
                  end if;
               end;
            end loop;
            Scheduled := Remaining;
         end;
         if Ada.Calendar.Clock - Last_Flush
           >= Duration'Max
                (0.01, Duration'Value (Environment ("SIM_SPEED", "1")) * 0.4)
         then
            Agent.Flush;
            Last_Flush := Ada.Calendar.Clock;
         end if;
         if Ada.Calendar.Clock - Last_Tick >= 1.0 then
            Agent.Tick;
            Last_Tick := Ada.Calendar.Clock;
         end if;
         if not Dashboard
           and Environment ("GITHUB_REPO") /= ""
           and Environment ("GITHUB_SOURCE", "poll") = "poll"
           and Ada.Calendar.Clock - Last_Poll
               >= Duration'Max
                    (0.1,
                     Duration'Value (Environment ("GITHUB_POLL_MS", "20000"))
                     / 1000)
         then
            Poller.Poll (Agent);
            Last_Poll := Ada.Calendar.Clock;
         end if;
         Broadcast;
      end loop;
      Finish;
   exception
      when others =>
         Finish;
         raise;
   end Run;
end Ambient.Server;
