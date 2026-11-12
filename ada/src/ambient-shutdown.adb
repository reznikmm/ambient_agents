with GNAT.Ctrl_C;
with System;

package body Ambient.Shutdown is
   Stopping : Boolean := False
   with Atomic;
   procedure Interrupt is
   begin
      Stopping := True;
   end Interrupt;
   procedure Terminate_Signal (Number : Integer)
   with Convention => C;
   procedure Terminate_Signal (Number : Integer) is
      pragma Unreferenced (Number);
   begin
      Stopping := True;
   end Terminate_Signal;
   function Signal
     (Number : Integer; Handler : System.Address) return System.Address
   with Import, Convention => C, External_Name => "signal";
   procedure Install is
      Previous : System.Address;
      pragma Unreferenced (Previous);
   begin
      Stopping := False;
      GNAT.Ctrl_C.Install_Handler (Interrupt'Access);
      Previous := Signal (15, Terminate_Signal'Address);
   end Install;
   function Requested return Boolean
   is (Stopping);
end Ambient.Shutdown;
