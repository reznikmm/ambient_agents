--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Trendy_Test;

package Test_Init is

   procedure Test_Ingest_And_Reset (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Thread (Op : in out Trendy_Test.Operation'Class);

end Test_Init;
