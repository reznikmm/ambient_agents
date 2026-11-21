--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Ambient_Agents.Workers;

package Ambient_Agents.Policies is

   type Policy_Route is (Act, Draft, Ask, Note);
   --  Apply an action, prepare a draft, request approval, or record a note.

   type Policy_Decision is record
      Route : Policy_Route;
      Ping  : Boolean;
      Why   : VSS.Strings.Virtual_String;
   end record;
   --  How to handle the worker's result and whether to notify the user now.

   type Policy is limited interface;
   --  Applies the user's preferences to a worker result.

   function Decide
     (Self : in out Policy; Result : Workers.Worker_Result)
      return Policy_Decision
   is abstract;
   --  Select a route and notification behavior, with an explanation.

end Ambient_Agents.Policies;
