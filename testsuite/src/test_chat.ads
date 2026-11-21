--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Trendy_Test;

package Test_Chat is

   procedure Test_Text_And_Reset (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Tool_Round_Trip (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Tool_Errors (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Provider_Errors (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Request_Limit (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Missing_Settings (Op : in out Trendy_Test.Operation'Class);

end Test_Chat;
