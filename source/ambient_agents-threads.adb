--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Ambient_Agents.Threads is

   procedure Append (Self : in out Thread; Item : Message) is
   begin
      Self.Items.Append (Item);
   end Append;

   procedure Clear (Self : in out Thread) is
   begin
      Self.Items.Clear;
   end Clear;

   procedure Iterate
     (Self : Thread; Process : not null access procedure (Item : Message)) is
   begin
      for Item of Self.Items loop
         Process (Item);
      end loop;
   end Iterate;

end Ambient_Agents.Threads;
