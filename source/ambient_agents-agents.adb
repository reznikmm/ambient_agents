--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers;

package body Ambient_Agents.Agents is

   procedure Ingest (Self : in out Agent; Event : Signals.Agent_Event) is
      use type Ada.Containers.Count_Type;
   begin
      Self.Events.Append (Event);

      if Self.Events.Length > 60 then
         Self.Events.Delete_First;
      end if;

      Self.Receipt_Count := @ + 1;
   end Ingest;

   procedure Reset (Self : in out Agent) is
   begin
      Self.Events.Clear;
      Self.Receipt_Count := 0;
   end Reset;

end Ambient_Agents.Agents;
