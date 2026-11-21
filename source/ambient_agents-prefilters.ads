--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Ambient_Agents.Signals;

package Ambient_Agents.Prefilters is

   type Filter_Result is record
      Keep   : Boolean;
      Reason : VSS.Strings.Virtual_String;
   end record;
   --  Whether the event should proceed to the gate and the reason.

   type Prefilter is limited interface;
   --  Screens events using local rules before the gate evaluates them.

   function Filter
     (Self : Prefilter; Event : Signals.Agent_Event) return Filter_Result
   is abstract;
   --  Evaluate one event against the prefilter rules.

end Ambient_Agents.Prefilters;
