--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Ambient_Agents.Sessions is

   procedure Send
     (Self    : in out Session;
      Message : VSS.Strings.Virtual_String;
      Emit    : not null access procedure (Part : Chat_Part))
   is
      pragma Unreferenced (Self, Message);
   begin
      Emit
        ((Kind    => Text,
          Content => "Chat is not implemented yet. See prompts/step-1.md."));
      Emit ((Kind => Done));
   end Send;

   procedure Reset (Self : in out Session) is
      pragma Unreferenced (Self);
   begin
      null;
   end Reset;

end Ambient_Agents.Sessions;
