--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Chat_Completions_API.Types;

private package Ambient_Agents.Demo_Tools is

   function Definitions
      return Chat_Completions_API.Types.ChatCompletionTool_Vector;
   --  The tools available to the workshop chat.

   procedure Execute
     (Call    : Chat_Completions_API.Types.ChatCompletionMessageToolCall;
      Result  : out VSS.Strings.Virtual_String;
      Success : out Boolean);
   --  Run a local tool. On failure, Result describes what went wrong.

end Ambient_Agents.Demo_Tools;
