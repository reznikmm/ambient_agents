--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Chat_Completions_API;
private with Chat_Completions_API.Types;

package Ambient_Agents.Sessions is

   type Part_Kind is (Text, Tool_Call, Tool_Result, Error, Done);
   --  Event kinds produced during a single turn. Done marks the end.

   type Chat_Part (Kind : Part_Kind) is record
      case Kind is
         when Text | Error =>
            Content : VSS.Strings.Virtual_String;

         when Tool_Call | Tool_Result =>
            Tool_Name : VSS.Strings.Virtual_String;
            Payload   : VSS.Strings.Virtual_String;
            --  Serialized arguments for a call or a preview of its result.

         when Done =>
            null;
      end case;
   end record;
   --  One event delivered to the caller while processing a message.

   type Session is private;
   --  The model-facing conversation state for one dialogue.

   procedure Configure
     (Self            : in out Session;
      URL             : VSS.Strings.Virtual_String;
      Model           : VSS.Strings.Virtual_String;
      Request_Handler : not null Chat_Completions_API.HTTP_Request_Access;
      API_Key         : VSS.Strings.Virtual_String :=
        VSS.Strings.Empty_Virtual_String);
   --  Set the connection settings. The handler must outlive its use by Self.

   procedure Send
     (Self    : in out Session;
      Message : VSS.Strings.Virtual_String;
      Emit    : not null access procedure (Part : Chat_Part));
   --  Process one user message. Call Emit synchronously for each part and
   --  finish with Done. Commit the model history on a completed turn.

   procedure Reset (Self : in out Session);
   --  Clear the model-facing conversation history.

private

   type Session is record
      URL             : VSS.Strings.Virtual_String;
      Model           : VSS.Strings.Virtual_String;
      API_Key         : VSS.Strings.Virtual_String;
      Request_Handler : Chat_Completions_API.HTTP_Request_Access;
      History         :
        Chat_Completions_API.Types.ChatCompletionRequestMessage_Vector;
      --  Completed turns, preceded by the most recent system message.
   end record;

end Ambient_Agents.Sessions;
