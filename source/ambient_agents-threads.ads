--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Vectors;

with VSS.Strings;

package Ambient_Agents.Threads is

   type Author is (User, Assistant, Report);
   --  Identifies chat participants and reports from the background agent.

   type Message is record
      From    : Author;
      Content : VSS.Strings.Virtual_String;
   end record;
   --  One entry in the user-visible conversation.

   package Message_Vectors is new Ada.Containers.Vectors (Positive, Message);

   type Thread is tagged private;
   --  An in-memory conversation displayed to the user, initially empty.

   procedure Append (Self : in out Thread; Item : Message);
   --  Add an entry after the existing messages.

   procedure Clear (Self : in out Thread);
   --  Remove all entries from the conversation.

   function Is_Empty (Self : Thread) return Boolean;
   --  Return True if there are no entries to display.

   procedure Iterate
     (Self : Thread; Process : not null access procedure (Item : Message));
   --  Call Process once for each message in insertion order.

private

   type Thread is tagged record
      Items : Message_Vectors.Vector;
   end record;

   function Is_Empty (Self : Thread) return Boolean
   is (Self.Items.Is_Empty);

end Ambient_Agents.Threads;
