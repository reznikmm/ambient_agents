with Ada.Directories;
with ACP.Types;
with ACP.Types.Inputs;
with ACP.Types.Outputs;
with GNAT.OS_Lib;
with Ambient.Codecs;
with Ambient.Support;

package body Ambient.ACP_Client is
   use Ambient.JSON, Ambient.Support;
   use type GNAT.Expect.Expect_Match;
   use type ACP.Types.Integer_64;
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   package Initialize_Requests is new
     Ambient.Codecs
       (ACP.Types.InitializeRequest,
        ACP.Types.Inputs.Input_InitializeRequest,
        ACP.Types.Outputs.Output_InitializeRequest);
   package Initialize_Replies is new
     Ambient.Codecs
       (ACP.Types.InitializeResponse,
        ACP.Types.Inputs.Input_InitializeResponse,
        ACP.Types.Outputs.Output_InitializeResponse);
   package New_Requests is new
     Ambient.Codecs
       (ACP.Types.NewSessionRequest,
        ACP.Types.Inputs.Input_NewSessionRequest,
        ACP.Types.Outputs.Output_NewSessionRequest);
   package New_Replies is new
     Ambient.Codecs
       (ACP.Types.NewSessionResponse,
        ACP.Types.Inputs.Input_NewSessionResponse,
        ACP.Types.Outputs.Output_NewSessionResponse);
   package Prompt_Requests is new
     Ambient.Codecs
       (ACP.Types.PromptRequest,
        ACP.Types.Inputs.Input_PromptRequest,
        ACP.Types.Outputs.Output_PromptRequest);
   package Prompt_Replies is new
     Ambient.Codecs
       (ACP.Types.PromptResponse,
        ACP.Types.Inputs.Input_PromptResponse,
        ACP.Types.Outputs.Output_PromptResponse);
   package Resume_Requests is new
     Ambient.Codecs
       (ACP.Types.ResumeSessionRequest,
        ACP.Types.Inputs.Input_ResumeSessionRequest,
        ACP.Types.Outputs.Output_ResumeSessionRequest);
   package Resume_Replies is new
     Ambient.Codecs
       (ACP.Types.ResumeSessionResponse,
        ACP.Types.Inputs.Input_ResumeSessionResponse,
        ACP.Types.Outputs.Output_ResumeSessionResponse);
   package Updates is new
     Ambient.Codecs
       (ACP.Types.UpdateSessionNotification,
        ACP.Types.Inputs.Input_UpdateSessionNotification,
        ACP.Types.Outputs.Output_UpdateSessionNotification);
   procedure Send (Self : in out Client; Item : Value) is
   begin
      GNAT.Expect.Send (Self.Process, Encode (Item));
   end Send;
   function Receive (Self : in out Client) return Value is
      Match : GNAT.Expect.Expect_Match;
   begin
      if Ada.Real_Time.Clock >= Self.Deadline then
         raise Program_Error with "ACP turn exceeded its deadline";
      end if;
      GNAT.Expect.Expect
        (Self.Process,
         Match,
         "[^\n]*\n",
         Timeout     =>
           Integer'Min
             (30_000,
              Integer
                (Ada.Real_Time.To_Duration
                   (Self.Deadline - Ada.Real_Time.Clock)
                 * 1000)),
         Full_Buffer => True);
      if Match = GNAT.Expect.Expect_Timeout then
         raise Program_Error with "ACP response timed out";
      elsif Match = GNAT.Expect.Expect_Full_Buffer then
         raise Program_Error with "ACP message exceeds 1 MiB";
      end if;
      declare
         Item : constant Value :=
           Parse (Trim (GNAT.Expect.Expect_Out_Match (Self.Process)));
      begin
         if Get_Text (Item, "jsonrpc") /= "2.0" then
            raise Constraint_Error with "invalid ACP JSON-RPC envelope";
         end if;
         return Item;
      end;
   end Receive;
   procedure Dispatch (Self : in out Client; Item : Value) is
      Method : constant String := Get_Text (Item, "method");
      Params : constant Value := Get (Item, "params");
      Update : constant Value := Get (Params, "update");
      Kind   : constant String := Get_Text (Update, "sessionUpdate");
      Id     : constant String := Get_Text (Update, "messageId");
      Typed  : ACP.Types.UpdateSessionNotification;
   begin
      if not Get (Item, "id").Is_Empty then
         if Method = "session/request_permission" then
            Self.Send
              (Response
                 (Get (Item, "id"),
                  Make_Object
                    ([("outcome",
                       Make_Object
                         ([("outcome", To_JSON_String ("cancelled"))]))])));
         else
            Self.Send
              (Error_Response
                 (Get (Item, "id"), -32601, "Unsupported client method"));
         end if;
      elsif Method = "session/update" then
         if not Updates.Decode (Params, Typed)
           or else Get_Text (Params, "sessionId")
                   /= To_UTF_8_String (Self.Current_Session)
         then
            raise Constraint_Error with "invalid ACP session update";
         end if;
         if Kind = "agent_message_chunk" or Kind = "agent_message" then
            if Id = "" then
               raise Constraint_Error with "ACP update missing messageId";
            end if;
            if Get (Self.Messages, Id).Is_Empty then
               Append (Self.Order, To_JSON_String (Id));
               Put (Self.Messages, Id, To_JSON_String (""));
            end if;
            if Kind = "agent_message_chunk" then
               declare
                  Content : constant Value := Get (Update, "content");
               begin
                  if Get_Text (Content, "type") = "text" then
                     Put
                       (Self.Messages,
                        Id,
                        To_JSON_String
                          (Get_Text (Self.Messages, Id)
                           & Get_Text (Content, "text")));
                  end if;
               end;
            elsif not Get (Update, "content").Is_Empty then
               declare
                  Content : constant Value := Get (Update, "content");
                  Text    : VSS.Strings.Virtual_String;
               begin
                  for J in 1 .. Length (Content) loop
                     if Get_Text (Element (Content, J), "type") = "text" then
                        Text.Append
                          (To_Virtual_String
                             (Get_Text (Element (Content, J), "text")));
                     end if;
                  end loop;
                  Put
                    (Self.Messages,
                     Id,
                     To_JSON_String (To_UTF_8_String (Text)));
               end;
            end if;
         elsif Kind = "state_update" then
            if Get_Text (Update, "state") /= "idle" then
               Self.Foreground := True;
            elsif Self.Foreground then
               if Get_Text (Update, "stopReason")
                  in "error" | "cancelled" | "refusal"
               then
                  raise Program_Error
                    with "ACP turn ended: " & Get_Text (Update, "stopReason");
               end if;
               Self.Idle := True;
            end if;
         end if;
      end if;
   end Dispatch;
   function Call
     (Self : in out Client; Method : String; Params : Value) return Value
   is
      Id : Value;
   begin
      Self.Sequence := Self.Sequence + 1;
      Id := To_JSON_Integer (Self.Sequence);
      Self.Send (Request (Id, To_Virtual_String (Method), Params));
      loop
         declare
            Item : constant Value := Receive (Self);
         begin
            if not Get (Item, "method").Is_Empty then
               Dispatch (Self, Item);
            elsif Encode (Get (Item, "id")) /= Encode (Id) then
               raise Constraint_Error with "ACP response id mismatch";
            elsif not Get (Item, "error").Is_Empty then
               raise Program_Error
                 with
                   "ACP "
                   & Method
                   & ": "
                   & Get_Text (Get (Item, "error"), "message");
            else
               return Get (Item, "result");
            end if;
         end;
      end loop;
   end Call;
   procedure Start (Self : in out Client; Program : String) is
      Input  : ACP.Types.InitializeRequest;
      Output : ACP.Types.InitializeResponse;
      Result : Value;
      Empty  : GNAT.OS_Lib.Argument_List (1 .. 0);
   begin
      if Self.Running then
         return;
      end if;
      GNAT.Expect.Non_Blocking_Spawn
        (Self.Process, Program, Empty, Buffer_Size => 1_048_576);
      Self.Running := True;
      Self.Deadline := Ada.Real_Time.Clock + Ada.Real_Time.Seconds (30);
      Input.protocolVersion := 2;
      Input.info.name := "ada-ambient-workshop";
      Input.info.version := "0.1.0";
      Result := Call (Self, "initialize", Initialize_Requests.Encode (Input));
      if not Initialize_Replies.Decode (Result, Output)
        or else Output.protocolVersion /= 2
        or else not Output.capabilities.Is_Set
        or else not Output.capabilities.Value.session.Is_Set
      then
         raise Program_Error with "ACP adapter must support protocol v2";
      end if;
   exception
      when others =>
         Self.Stop;
         raise;
   end Start;
   procedure Stop (Self : in out Client) is
   begin
      if Self.Running then
         GNAT.Expect.Close (Self.Process);
         Self.Running := False;
         Self.Sessions := Object_Value;
      end if;
   end Stop;
   function Session (Self : Client; Key : String) return String
   is (Get_Text (Self.Sessions, Key));
   function Prompt
     (Self              : in out Client;
      Session_Key, Text : String;
      Resume_Id         : String := "") return String
   is
      New_Input     : ACP.Types.NewSessionRequest;
      New_Output    : ACP.Types.NewSessionResponse;
      Input         : ACP.Types.PromptRequest;
      Output        : ACP.Types.PromptResponse;
      Result        : Value;
      Answer        : VSS.Strings.Virtual_String;
      Resume_Input  : ACP.Types.ResumeSessionRequest;
      Resume_Output : ACP.Types.ResumeSessionResponse;
   begin
      if not Self.Running then
         Self.Start (Environment ("ACP_AGENT", "claude-agent-acp"));
      end if;
      Self.Deadline := Ada.Real_Time.Clock + Ada.Real_Time.Seconds (300);
      if Self.Session (Session_Key) = "" and Resume_Id /= "" then
         Self.Current_Session := To_Virtual_String (Resume_Id);
         Resume_Input.sessionId := Self.Current_Session;
         Resume_Input.cwd :=
           To_Virtual_String (Ada.Directories.Current_Directory);
         Resume_Input.mcpServers := Array_Value;
         Result :=
           Call
             (Self, "session/resume", Resume_Requests.Encode (Resume_Input));
         if not Resume_Replies.Decode (Result, Resume_Output) then
            raise Constraint_Error with "invalid ACP session/resume response";
         end if;
         Put (Self.Sessions, Session_Key, To_JSON_String (Resume_Id));
      end if;
      if Self.Session (Session_Key) = "" then
         New_Input.cwd :=
           To_Virtual_String (Ada.Directories.Current_Directory);
         New_Input.mcpServers := Array_Value;
         Result := Call (Self, "session/new", New_Requests.Encode (New_Input));
         if not New_Replies.Decode (Result, New_Output)
           or else New_Output.sessionId.Is_Empty
         then
            raise Constraint_Error
              with "ACP session/new returned no sessionId";
         end if;
         Put
           (Self.Sessions,
            Session_Key,
            To_JSON_String (To_UTF_8_String (New_Output.sessionId)));
      end if;
      Self.Current_Session := To_Virtual_String (Self.Session (Session_Key));
      Self.Messages := Object_Value;
      Self.Order := Array_Value;
      Self.Idle := False;
      Self.Foreground := False;
      Input.sessionId := Self.Current_Session;
      Input.prompt :=
        Make_Array
          ([Make_Object
              ([("type", To_JSON_String ("text")),
                ("text", To_JSON_String (Text))])]);
      Result := Call (Self, "session/prompt", Prompt_Requests.Encode (Input));
      if not Prompt_Replies.Decode (Result, Output)
        or else Output.messageId.Is_Empty
      then
         raise Constraint_Error with "invalid ACP prompt acceptance";
      end if;
      while not Self.Idle loop
         Dispatch (Self, Receive (Self));
      end loop;
      for J in 1 .. Length (Self.Order) loop
         Answer.Append
           (To_Virtual_String
              (Get_Text (Self.Messages, Get_Text (Element (Self.Order, J)))));
      end loop;
      return To_UTF_8_String (Answer);
   exception
      when others =>
         Self.Stop;
         raise;
   end Prompt;
end Ambient.ACP_Client;
