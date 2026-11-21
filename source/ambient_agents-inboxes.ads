--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ambient_Agents.Signals;

package Ambient_Agents.Inboxes is

   type Offer_Result is (Started, Merged);
   --  Indicates whether an event started work or joined existing work.

   type Inbox is limited interface;
   --  Groups incoming events by subject before the worker handles them.

   function Offer
     (Self : in out Inbox; Event : Signals.Agent_Event) return Offer_Result
   is abstract;
   --  Submit an event for its subject and report how it was handled.

end Ambient_Agents.Inboxes;
