--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ambient_Agents.Signals;

package Ambient_Agents.Agents is

   type Agent is private;
   --  State for one agent, including its event count and recent history.

   procedure Ingest (Self : in out Agent; Event : Signals.Agent_Event);
   --  Accept a normalized event from any source. Step 0 only records it.

   function Received (Self : Agent) return Natural;
   --  Return the total number of events accepted since the last reset.

   function Recent_Events (Self : Agent) return Signals.Event_Vectors.Vector;
   --  The most recent 60 events, oldest first.

   procedure Reset (Self : in out Agent);
   --  Clear the event history and reset the count to zero.

private

   type Agent is record
      Receipt_Count : Natural := 0;
      Events        : Signals.Event_Vectors.Vector;
   end record;

   function Received (Self : Agent) return Natural
   is (Self.Receipt_Count);

   function Recent_Events (Self : Agent) return Signals.Event_Vectors.Vector
   is (Self.Events);

end Ambient_Agents.Agents;
