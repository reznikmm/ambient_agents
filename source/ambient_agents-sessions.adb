--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Exceptions;

with VSS.Strings.Conversions;
with VSS.Strings.Cursors.Iterators.Characters;

with Chat_Completions_API.Chats;

with Ambient_Agents.Demo_Tools;

package body Ambient_Agents.Sessions is

   use VSS.Strings;
   use Chat_Completions_API.Types;

   System_Instructions : constant Virtual_String :=
     "You are the Ambient Agents workshop assistant. When asked about open"
     & " issues, use list_open_issues to get the sample project issues. Base"
     & " recommendations on those issues and explain your choice.";

   Max_Requests   : constant := 10;
   Preview_Length : constant := 400;

   function Preview (Result : Virtual_String) return Virtual_String;
   --  Copy up to Preview_Length Unicode characters from the tool result.

   procedure Configure
     (Self            : in out Session;
      URL             : Virtual_String;
      Model           : Virtual_String;
      Request_Handler : not null Chat_Completions_API.HTTP_Request_Access;
      API_Key         : Virtual_String := Empty_Virtual_String) is
   begin
      Self.URL := URL;
      Self.Model := Model;
      Self.API_Key := API_Key;
      Self.Request_Handler := Request_Handler;
   end Configure;

   function Preview (Result : Virtual_String) return Virtual_String is
      Last : VSS.Strings.Cursors.Iterators.Characters.Character_Iterator :=
        Result.Before_First_Character;
   begin
      for Index in 1 .. Preview_Length loop
         if not Last.Forward then
            return Result;
         end if;
      end loop;

      return Result.Slice (Result.At_First_Character, Last);
   end Preview;

   procedure Reset (Self : in out Session) is
   begin
      Self.History := [];
   end Reset;

   procedure Send
     (Self    : in out Session;
      Message : Virtual_String;
      Emit    : not null access procedure (Part : Chat_Part))
   is
      use type Chat_Completions_API.HTTP_Request_Access;

      procedure Report_Error (Content : Virtual_String);
      --  Emit a diagnostic for this turn.

      procedure Run_Turn;
      --  Work on a provisional history until the model gives a final reply.

      procedure Report_Error (Content : Virtual_String) is
      begin
         Emit ((Kind => Error, Content => Content));
      end Report_Error;

      procedure Run_Turn is
         Server         : Chat_Completions_API.Server;
         Messages       : ChatCompletionRequestMessage_Vector := Self.History;
         System_Message : constant ChatCompletionRequestMessage :=
           (role => system, content => System_Instructions, others => <>);
         Tools          : constant ChatCompletionTool_Vector :=
           Demo_Tools.Definitions;

         procedure Request
           (Response : out CreateChatCompletionResponse;
            Failure  : out Virtual_String);
         --  Fetch one response and report any provider failure.

         procedure Handle_Call (Call : ChatCompletionMessageToolCall);
         --  Emit the call and append its complete result to Messages.

         procedure Request
           (Response : out CreateChatCompletionResponse;
            Failure  : out Virtual_String)
         is
            Success : Boolean;
         begin
            Chat_Completions_API.Chats.Chat
              (Server,
               Model    => Self.Model,
               Messages => Messages,
               Tools    => Tools,
               Response => Response,
               Success  => Success);

            if Success then
               Failure := Empty_Virtual_String;
            else
               Failure :=
                 "Chat Completions request failed. Check CHAT_COMPLETIONS_URL,"
                 & " CHAT_COMPLETIONS_MODEL, and any required"
                 & " CHAT_COMPLETIONS_API_KEY.";
            end if;
         exception
            when E : others =>
               Failure :=
                 "Chat Completions request failed: "
                 & VSS.Strings.Conversions.To_Virtual_String
                     (Ada.Exceptions.Exception_Message (E));
         end Request;

         procedure Handle_Call (Call : ChatCompletionMessageToolCall) is
            Result  : Virtual_String;
            Success : Boolean;
         begin
            Emit
              ((Kind      => Tool_Call,
                Tool_Name => Call.a_function.name,
                Payload   => Call.a_function.arguments));
            Demo_Tools.Execute (Call, Result, Success);
            Messages.Append
              ((role         => tool,
                tool_call_id => Call.id,
                content      => Result,
                others       => <>));

            if Success then
               Emit
                 ((Kind      => Tool_Result,
                   Tool_Name => Call.a_function.name,
                   Payload   => Preview (Result)));
            else
               Report_Error (Result);
            end if;
         end Handle_Call;
      begin
         Server.Set_URL (Self.URL);
         Server.Set_Request_Handler (Self.Request_Handler);

         if not Self.API_Key.Is_Empty then
            Server.Set_API_Key (Self.API_Key);
         end if;

         if Messages.Length = 0 then
            Messages.Append (System_Message);
         else
            Messages (1) := System_Message;
         end if;

         Messages.Append ((role => user, content => Message, others => <>));

         for Attempt in 1 .. Max_Requests loop
            declare
               Response : CreateChatCompletionResponse;
               Failure  : Virtual_String;
            begin
               Request (Response, Failure);

               if not Failure.Is_Empty then
                  Report_Error (Failure);
                  return;
               elsif Response.choices.Length = 0 then
                  Report_Error ("Chat Completions returned no choices.");
                  return;
               end if;

               declare
                  Reply : ChatCompletionResponseMessage renames
                    Response.choices (1).message;
               begin
                  Messages.Append
                    ((role       => assistant,
                      content    => Reply.content,
                      tool_calls => Reply.tool_calls,
                      others     => <>));

                  if not Reply.content.Is_Empty then
                     Emit ((Kind => Text, Content => Reply.content));
                  end if;

                  if Reply.tool_calls.Length = 0 then
                     Self.History := Messages;
                     return;
                  end if;

                  for Index in 1 .. Reply.tool_calls.Length loop
                     if Reply.tool_calls (Index).id.Is_Empty then
                        Report_Error ("A model tool call has no call ID.");
                        return;
                     end if;

                     Handle_Call (Reply.tool_calls (Index));
                  end loop;
               end;
            end;
         end loop;

         Report_Error ("Chat turn exceeded the limit of ten model requests.");
      end Run_Turn;
   begin
      if Self.URL.Is_Empty then
         Report_Error
           ("Set CHAT_COMPLETIONS_URL to the full Chat Completions endpoint.");
      elsif Self.Model.Is_Empty then
         Report_Error
           ("Set CHAT_COMPLETIONS_MODEL to a model accepted by the server.");
      elsif Self.Request_Handler = null then
         Report_Error ("Configure a Chat Completions HTTP request handler.");
      else
         Run_Turn;
      end if;

      Emit ((Kind => Done));
   end Send;

end Ambient_Agents.Sessions;
