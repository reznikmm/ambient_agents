--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Vectors;

with VSS.Strings;

with Ambient_Agents.Signals;

package Ambient_Agents.Gates is

   type Gate_Action is (Act, Ignore, Ask);
   --  Allow work, ignore the event, or ask the user for a decision.

   type Verdict is record
      Identifier : VSS.Strings.Virtual_String;
      Action     : Gate_Action;
      Reason     : VSS.Strings.Virtual_String;
   end record;
   --  A gate decision and its explanation, keyed by event identifier.

   package Verdict_Vectors is new Ada.Containers.Vectors (Positive, Verdict);

   type Gate is limited interface;
   --  Reviews events that have passed the prefilter.

   function Decide
     (Self : in out Gate; Events : Signals.Event_Vectors.Vector)
      return Verdict_Vectors.Vector
   is abstract;
   --  Evaluate a batch of events and return a verdict for each event.

end Ambient_Agents.Gates;
