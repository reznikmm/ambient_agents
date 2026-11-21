--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.IO_Exceptions;

with VSS.IRIs;
with VSS.JSON.Pull_Readers.Simple;
with VSS.JSON.Push_Writers;
with VSS.Stream_Element_Vectors;
with VSS.Strings;
with VSS.Text_Streams.Memory_UTF8_Input;
with VSS.Text_Streams.Memory_UTF8_Output;

with Chat_Completions_API.HTTP_Requests;
with Chat_Completions_API.Types.Inputs;
with Chat_Completions_API.Types.Outputs;

with Ambient_Agents.Sessions;

package body Test_Chat is

   use Ambient_Agents.Sessions;
   use Chat_Completions_API.Types;
   use VSS.Stream_Element_Vectors;
   use VSS.Strings;
   use type Ada.Containers.Count_Type;

   Endpoint : constant Virtual_String := "http://example.test/chat";
   Model    : constant Virtual_String := "test-model";

   List_Issues : constant ChatCompletionMessageToolCall :=
     (id         => "call_issues",
      a_function => (name => "list_open_issues", arguments => "{  }"));

   type Posted_Request is record
      URL           : Virtual_String;
      Content_Type  : Virtual_String;
      Authorization : Virtual_String;
      Data          : Stream_Element_Vector;
   end record;

   type Scripted_Reply is record
      Choices : ChatCompletionChoice_Vector;
      Status  : Natural := 200;
      --  Zero scripts a transport exception.
   end record;

   package Request_Vectors is new
     Ada.Containers.Vectors (Positive, Posted_Request);
   package Reply_Vectors is new
     Ada.Containers.Vectors (Positive, Scripted_Reply);

   type Fake_HTTP is limited
     new Chat_Completions_API.HTTP_Requests.HTTP_Request
   with record
      Requests : Request_Vectors.Vector;
      Replies  : Reply_Vectors.Vector;
   end record;

   overriding
   procedure Post
     (Self          : in out Fake_HTTP;
      URL           : VSS.IRIs.IRI;
      Content_Type  : Virtual_String;
      Authorization : Virtual_String;
      Output        : Stream_Element_Vector;
      Response      : out Stream_Element_Vector;
      Status_Code   : out Natural);

   function Answer (Content : Virtual_String) return Scripted_Reply;

   function Calls
     (Tool_Calls : ChatCompletionMessageToolCall_Vector;
      Content    : Virtual_String := Empty_Virtual_String)
      return Scripted_Reply;

   function Request
     (Op       : in out Trendy_Test.Operation'Class;
      HTTP     : Fake_HTTP'Class;
      Position : Positive) return CreateChatCompletionRequest;
   --  Decode the full request sent through the fake transport.

   type Recorded_Part is record
      Kind    : Part_Kind;
      Name    : Virtual_String;
      Payload : Virtual_String;
   end record;

   package Part_Vectors is new
     Ada.Containers.Vectors (Positive, Recorded_Part);
   type Part_Sequence is array (Positive range <>) of Part_Kind;

   procedure Check_Turn
     (Op           : in out Trendy_Test.Operation'Class;
      Conversation : in out Session;
      Message      : Virtual_String;
      Expected     : Part_Sequence;
      Parts        : out Part_Vectors.Vector);
   --  Verify the exact event sequence, including a single final Done.

   overriding
   procedure Post
     (Self          : in out Fake_HTTP;
      URL           : VSS.IRIs.IRI;
      Content_Type  : Virtual_String;
      Authorization : Virtual_String;
      Output        : Stream_Element_Vector;
      Response      : out Stream_Element_Vector;
      Status_Code   : out Natural)
   is
      Writer : VSS.JSON.Push_Writers.JSON_Simple_Push_Writer;
      Stream :
        aliased VSS.Text_Streams.Memory_UTF8_Output.Memory_UTF8_Output_Stream;
   begin
      Self.Requests.Append
        (Posted_Request'
           (URL.To_Virtual_String, Content_Type, Authorization, Output));

      declare
         Reply : constant Scripted_Reply :=
           Self.Replies (Self.Requests.Last_Index);
      begin
         Status_Code := Reply.Status;

         if Status_Code = 0 then
            raise Ada.IO_Exceptions.Device_Error with "scripted POST failure";
         end if;

         Writer.Set_Stream (Stream'Unchecked_Access);
         Writer.Start_Document;
         Outputs.Output_CreateChatCompletionResponse
           (Writer,
            (id      => "completion",
             choices => Reply.Choices,
             created => 1,
             model   => Model,
             others  => <>));
         Writer.End_Document;
         Response := Stream.Buffer;
      end;
   end Post;

   function Answer (Content : Virtual_String) return Scripted_Reply is
   begin
      return
        (Choices =>
           [(finish_reason => stop,
             index         => 0,
             message       => (content => Content, others => <>),
             others        => <>)],
         Status  => 200);
   end Answer;

   function Calls
     (Tool_Calls : ChatCompletionMessageToolCall_Vector;
      Content    : Virtual_String := Empty_Virtual_String)
      return Scripted_Reply is
   begin
      return
        (Choices =>
           [(finish_reason => Chat_Completions_API.Types.tool_calls,
             index         => 0,
             message       =>
               (content => Content, tool_calls => Tool_Calls, others => <>),
             others        => <>)],
         Status  => 200);
   end Calls;

   function Request
     (Op       : in out Trendy_Test.Operation'Class;
      HTTP     : Fake_HTTP'Class;
      Position : Positive) return CreateChatCompletionRequest
   is
      Stream :
        aliased VSS.Text_Streams.Memory_UTF8_Input.Memory_UTF8_Input_Stream;
      Reader : VSS.JSON.Pull_Readers.Simple.JSON_Simple_Pull_Reader;
      Value  : CreateChatCompletionRequest;
      Parsed : Boolean;
   begin
      Stream.Set_Data (HTTP.Requests (Position).Data);
      Reader.Set_Stream (Stream'Unchecked_Access);
      Reader.Read_Next;
      Parsed := Reader.Is_Start_Document;
      Reader.Read_Next;
      Inputs.Input_CreateChatCompletionRequest (Reader, Value, Parsed);
      Op.Assert (Parsed and then Reader.Is_End_Document);
      return Value;
   end Request;

   procedure Check_Turn
     (Op           : in out Trendy_Test.Operation'Class;
      Conversation : in out Session;
      Message      : Virtual_String;
      Expected     : Part_Sequence;
      Parts        : out Part_Vectors.Vector)
   is
      procedure Record_Part (Part : Chat_Part);
      --  Keep the observable fields of each part for assertions.

      procedure Record_Part (Part : Chat_Part) is
      begin
         case Part.Kind is
            when Text | Error            =>
               Parts.Append (Recorded_Part'(Part.Kind, "", Part.Content));

            when Tool_Call | Tool_Result =>
               Parts.Append
                 (Recorded_Part'(Part.Kind, Part.Tool_Name, Part.Payload));

            when Done                    =>
               Parts.Append (Recorded_Part'(Done, "", ""));
         end case;
      end Record_Part;
   begin
      Parts.Clear;
      Send (Conversation, Message, Record_Part'Access);
      Op.Assert (Natural (Parts.Length) = Expected'Length);

      for Index in Expected'Range loop
         Op.Assert (Parts (Index).Kind = Expected (Index));
      end loop;
   end Check_Turn;

   procedure Test_Text_And_Reset (Op : in out Trendy_Test.Operation'Class) is
      HTTP               : aliased Fake_HTTP;
      Conversation       : Session;
      Parts              : Part_Vectors.Vector;
      First, Next, Fresh : CreateChatCompletionRequest;
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, Endpoint, Model, HTTP'Unchecked_Access, "key");
      HTTP.Replies.Append (Answer ("Hello, Zoë"));
      HTTP.Replies.Append (Answer ("We were discussing the demo."));
      HTTP.Replies.Append (Answer ("Starting over."));

      Check_Turn (Op, Conversation, "Hi, I'm Zoë", [Text, Done], Parts);
      Op.Assert (Parts (1).Payload = "Hello, Zoë");
      Check_Turn
        (Op, Conversation, "What were we discussing?", [Text, Done], Parts);
      Reset (Conversation);
      Check_Turn (Op, Conversation, "A new chat", [Text, Done], Parts);
      Op.Assert (HTTP.Requests.Length = 3);

      Op.Assert (HTTP.Requests (1).URL = Endpoint);
      Op.Assert (HTTP.Requests (1).Content_Type = "application/json");
      Op.Assert (HTTP.Requests (1).Authorization = "Bearer key");
      First := Request (Op, HTTP, 1);
      Next := Request (Op, HTTP, 2);
      Fresh := Request (Op, HTTP, 3);
      Op.Assert (First.model = Model);
      Op.Assert (First.messages.Length = 2);
      Op.Assert (First.messages (1).role = system);
      Op.Assert (not First.messages (1).content.Is_Empty);
      Op.Assert (First.messages (2).role = user);
      Op.Assert (First.messages (2).content = "Hi, I'm Zoë");
      Op.Assert (Next.messages.Length = 4);
      Op.Assert (Next.messages (1).content = First.messages (1).content);
      Op.Assert (Next.messages (2).content = First.messages (2).content);
      Op.Assert (Next.messages (3).role = assistant);
      Op.Assert (Next.messages (3).content = "Hello, Zoë");
      Op.Assert (Next.messages (4).content = "What were we discussing?");
      Op.Assert (Fresh.messages.Length = 2);
      Op.Assert (Fresh.messages (1).role = system);
      Op.Assert (Fresh.messages (2).content = "A new chat");
   end Test_Text_And_Reset;

   procedure Test_Tool_Round_Trip (Op : in out Trendy_Test.Operation'Class) is
      HTTP                   : aliased Fake_HTTP;
      Conversation           : Session;
      Parts                  : Part_Vectors.Vector;
      First, Next, Follow_Up : CreateChatCompletionRequest;
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, Endpoint, Model, HTTP'Unchecked_Access);
      HTTP.Replies.Append (Calls ([List_Issues], "I'll check the issues."));
      HTTP.Replies.Append (Answer ("Start with issue #12."));
      HTTP.Replies.Append (Answer ("It reduces flaky CI failures."));

      Check_Turn
        (Op,
         Conversation,
         "What should we pick first?",
         [Text, Tool_Call, Tool_Result, Text, Done],
         Parts);
      Op.Assert (Parts (1).Payload = "I'll check the issues.");
      Op.Assert (Parts (2).Name = List_Issues.a_function.name);
      Op.Assert (Parts (2).Payload = List_Issues.a_function.arguments);
      Op.Assert (Parts (3).Name = List_Issues.a_function.name);
      Op.Assert (Parts (3).Payload.Character_Length = 400);
      Op.Assert (Parts (4).Payload = "Start with issue #12.");

      First := Request (Op, HTTP, 1);
      Next := Request (Op, HTTP, 2);
      Op.Assert (First.tools.Length = 1);
      Op.Assert (First.tools (1).a_function.name = "list_open_issues");
      Op.Assert (First.tools (1).a_function.parameters.Is_Set);
      Op.Assert (Next.tools.Length = 1);
      Op.Assert (Next.messages.Length = 4);
      Op.Assert (Next.messages (3).role = assistant);
      Op.Assert (Next.messages (3).content = Parts (1).Payload);
      Op.Assert (Next.messages (3).tool_calls.Length = 1);
      Op.Assert (Next.messages (3).tool_calls (1) = List_Issues);
      Op.Assert (Next.messages (4).role = tool);
      Op.Assert (Next.messages (4).tool_call_id = List_Issues.id);
      Op.Assert (Next.messages (4).content.Character_Length > 400);
      Op.Assert (Next.messages (4).content.Starts_With (Parts (3).Payload));
      Op.Assert (Next.messages (4).content.Ends_With ("source event."));

      Check_Turn (Op, Conversation, "Why that one?", [Text, Done], Parts);
      Op.Assert (HTTP.Requests.Length = 3);
      Follow_Up := Request (Op, HTTP, 3);
      Op.Assert (Follow_Up.messages.Length = 6);
      Op.Assert (Follow_Up.messages (3).tool_calls (1) = List_Issues);
      Op.Assert (Follow_Up.messages (4).role = tool);
      Op.Assert (Follow_Up.messages (4).tool_call_id = List_Issues.id);
      Op.Assert (Follow_Up.messages (4).content = Next.messages (4).content);
      Op.Assert (Follow_Up.messages (5).content = "Start with issue #12.");
      Op.Assert (Follow_Up.messages (6).content = "Why that one?");
   end Test_Tool_Round_Trip;

   procedure Test_Tool_Errors (Op : in out Trendy_Test.Operation'Class) is
      HTTP         : aliased Fake_HTTP;
      Conversation : Session;
      Parts        : Part_Vectors.Vector;
      Next         : CreateChatCompletionRequest;

      Unknown : constant ChatCompletionMessageToolCall :=
        (id => "call_unknown", a_function => ("unknown_tool", "{}"));
      Invalid : constant ChatCompletionMessageToolCall :=
        (id => "call_invalid", a_function => ("list_open_issues", "[]"));
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, Endpoint, Model, HTTP'Unchecked_Access);
      HTTP.Replies.Append (Calls ([Unknown, Invalid]));
      HTTP.Replies.Append (Answer ("I couldn't list the issues."));

      Check_Turn
        (Op,
         Conversation,
         "What are the issues?",
         [Tool_Call, Error, Tool_Call, Error, Text, Done],
         Parts);
      Op.Assert (Parts (1).Name = Unknown.a_function.name);
      Op.Assert (Parts (2).Payload.Ends_With ("unknown_tool"));
      Op.Assert (Parts (3).Payload = Invalid.a_function.arguments);
      Op.Assert (Parts (4).Payload.Ends_With ("empty JSON object ({})."));
      Op.Assert (HTTP.Requests.Length = 2);

      Next := Request (Op, HTTP, 2);
      Op.Assert (Next.messages.Length = 5);
      Op.Assert (Next.messages (3).tool_calls.Length = 2);
      Op.Assert (Next.messages (4).role = tool);
      Op.Assert (Next.messages (4).tool_call_id = Unknown.id);
      Op.Assert (Next.messages (4).content = Parts (2).Payload);
      Op.Assert (Next.messages (5).role = tool);
      Op.Assert (Next.messages (5).tool_call_id = Invalid.id);
      Op.Assert (Next.messages (5).content = Parts (4).Payload);
   end Test_Tool_Errors;

   procedure Test_Provider_Errors (Op : in out Trendy_Test.Operation'Class) is
      HTTP         : aliased Fake_HTTP;
      Conversation : Session;
      Parts        : Part_Vectors.Vector;
      Next         : CreateChatCompletionRequest;
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, Endpoint, Model, HTTP'Unchecked_Access);
      HTTP.Replies.Append (Answer ("Prior answer"));
      HTTP.Replies.Append (Calls ([List_Issues]));
      HTTP.Replies.Append (Scripted_Reply'(Choices => [], Status => 503));
      HTTP.Replies.Append (Scripted_Reply'(Choices => [], Status => 200));
      HTTP.Replies.Append (Scripted_Reply'(Choices => [], Status => 0));
      HTTP.Replies.Append (Answer ("Recovered"));

      Check_Turn (Op, Conversation, "Prior question", [Text, Done], Parts);
      Check_Turn
        (Op,
         Conversation,
         "Unavailable",
         [Tool_Call, Tool_Result, Error, Done],
         Parts);
      Check_Turn (Op, Conversation, "No choices", [Error, Done], Parts);
      Op.Assert (Parts (1).Payload.Ends_With ("no choices."));
      Check_Turn (Op, Conversation, "Transport failure", [Error, Done], Parts);
      Op.Assert (Parts (1).Payload.Ends_With ("scripted POST failure"));
      Check_Turn (Op, Conversation, "Try again", [Text, Done], Parts);
      Op.Assert (HTTP.Requests.Length = 6);

      for Index in 4 .. 6 loop
         Next := Request (Op, HTTP, Index);
         Op.Assert (Next.messages.Length = 4);
         Op.Assert (Next.messages (2).content = "Prior question");
         Op.Assert (Next.messages (3).content = "Prior answer");
      end loop;
   end Test_Provider_Errors;

   procedure Test_Request_Limit (Op : in out Trendy_Test.Operation'Class) is
      HTTP         : aliased Fake_HTTP;
      Conversation : Session;
      Parts        : Part_Vectors.Vector;
      Expected     : Part_Sequence (1 .. 22);
      Next         : CreateChatCompletionRequest;
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, Endpoint, Model, HTTP'Unchecked_Access);

      for Index in 1 .. 10 loop
         if Index < 10 then
            HTTP.Replies.Append (Calls ([List_Issues]));
         end if;

         Expected (2 * Index - 1 .. 2 * Index) := [Tool_Call, Tool_Result];
      end loop;

      HTTP.Replies.Append (Answer ("Finished on the tenth request"));
      Check_Turn
        (Op,
         Conversation,
         "Finish on ten",
         Expected (1 .. 18) & [Text, Done],
         Parts);
      Op.Assert (HTTP.Requests.Length = 10);

      for Index in 1 .. 10 loop
         HTTP.Replies.Append (Calls ([List_Issues]));
      end loop;

      HTTP.Replies.Append (Answer ("Fresh turn"));
      Expected (21 .. 22) := [Error, Done];
      Check_Turn (Op, Conversation, "Keep calling tools", Expected, Parts);
      Op.Assert (Parts (21).Payload.Ends_With ("ten model requests."));
      Op.Assert (HTTP.Requests.Length = 20);

      Check_Turn (Op, Conversation, "After the limit", [Text, Done], Parts);
      Next := Request (Op, HTTP, 21);
      Op.Assert (Next.messages.Length = 22);
      Op.Assert (Next.messages (2).content = "Finish on ten");
      Op.Assert (Next.messages (21).content = "Finished on the tenth request");
      Op.Assert (Next.messages (22).content = "After the limit");
   end Test_Request_Limit;

   procedure Test_Missing_Settings (Op : in out Trendy_Test.Operation'Class) is
      HTTP         : aliased Fake_HTTP;
      Conversation : Session;
      Parts        : Part_Vectors.Vector;
   begin
      Op.Register (Parallelize => False);
      Configure (Conversation, "", Model, HTTP'Unchecked_Access);
      Check_Turn (Op, Conversation, "Missing URL", [Error, Done], Parts);
      Op.Assert (Parts (1).Payload.Starts_With ("Set CHAT_COMPLETIONS_URL"));

      Configure (Conversation, Endpoint, "", HTTP'Unchecked_Access);
      Check_Turn (Op, Conversation, "Missing model", [Error, Done], Parts);
      Op.Assert (Parts (1).Payload.Starts_With ("Set CHAT_COMPLETIONS_MODEL"));
      Op.Assert (HTTP.Requests.Is_Empty);
   end Test_Missing_Settings;

end Test_Chat;
