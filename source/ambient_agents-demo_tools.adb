--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Latin_1;

with VSS.JSON.Streams;
with VSS.String_Vectors;
with VSS.Strings.Conversions;

package body Ambient_Agents.Demo_Tools is

   use VSS.JSON.Streams;
   use VSS.Strings;

   List_Open_Issues : constant Virtual_String := "list_open_issues";

   Issue_Lines : constant VSS.String_Vectors.Virtual_String_Vector :=
     ["#12 — Retry transient CI failures. The runner should retry a job once"
      & " when the artifact service returns a temporary error. Keep the"
      & " original failure visible in the job summary.",
      "#18 — Document local model setup. Add an example configuration for"
      & " running the workshop against llama.cpp, with a sample command and"
      & " an explanation of how to select a tool-capable model.",
      "#23 — Clarify duplicate event reports. Include the original event ID"
      & " in the report so maintainers can match repeated deliveries to the"
      & " source event."];

   Open_Issues : constant Virtual_String :=
     Issue_Lines.Join_Lines (LF, Terminate_Last => False);

   function Has_No_Arguments (Arguments : Virtual_String) return Boolean;
   --  Accept an empty JSON object with optional JSON whitespace.

   function Definitions
      return Chat_Completions_API.Types.ChatCompletionTool_Vector is
   begin
      return
        [(a_function =>
            (name        => List_Open_Issues,
             description => "List the open issues in the sample project.",
             parameters  =>
               (Is_Set => True,
                Value  =>
                  [(Kind => Start_Object),
                   (Key_Name, "type"),
                   (String_Value, "object"),
                   (Key_Name, "properties"),
                   (Kind => Start_Object),
                   (Kind => End_Object),
                   (Key_Name, "additionalProperties"),
                   (Boolean_Value, False),
                   (Kind => End_Object)]),
             strict      => False))];
   end Definitions;

   procedure Execute
     (Call    : Chat_Completions_API.Types.ChatCompletionMessageToolCall;
      Result  : out Virtual_String;
      Success : out Boolean) is
   begin
      Success := False;

      if Call.a_function.name /= List_Open_Issues then
         Result := "Unknown tool: " & Call.a_function.name;
      elsif not Has_No_Arguments (Call.a_function.arguments) then
         Result := List_Open_Issues & " expects an empty JSON object ({}).";
      else
         Result := Open_Issues;
         Success := True;
      end if;
   end Execute;

   function Has_No_Arguments (Arguments : Virtual_String) return Boolean is
      package Latin_1 renames Ada.Characters.Latin_1;

      Empty_Object : constant String := "{}";
      Position     : Positive := Empty_Object'First;
   begin
      for Byte of VSS.Strings.Conversions.To_UTF_8_String (Arguments) loop
         if Byte not in ' ' | Latin_1.HT | Latin_1.CR | Latin_1.LF then
            if Position > Empty_Object'Last
              or else Byte /= Empty_Object (Position)
            then
               return False;
            end if;

            Position := @ + 1;
         end if;
      end loop;

      return Position > Empty_Object'Last;
   end Has_No_Arguments;

end Ambient_Agents.Demo_Tools;
