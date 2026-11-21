--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Ambient_Agents.Signals;

package Ambient_Agents.Workers is

   type Worker_Result is record
      Session_Identifier : VSS.Strings.Virtual_String;
      Summary            : VSS.Strings.Virtual_String;
      Action             : VSS.Strings.Virtual_String;
      Reversible         : Boolean;
      Confidence         : Float range 0.0 .. 1.0;
      Wakeup_Delay       : Duration := 0.0;
      --  A positive delay requests a follow-up.
   end record;
   --  The worker's session, proposed action, and optional follow-up.

   type Worker is limited interface;
   --  Processes routed events and reports a result for policy review.

   function Run
     (Self   : in out Worker;
      Signal : Signals.Signal;
      Events : Signals.Event_Vectors.Vector) return Worker_Result
   is abstract;
   --  Process a batch assigned to one signal category.

end Ambient_Agents.Workers;
