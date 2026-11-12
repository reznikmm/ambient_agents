--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with ACP.Types;
with VSS.Stream_Element_Vectors;
with VSS.Strings;

package Ambient.JSON is
   subtype Value is ACP.Types.Any_Value;

   function Parse
     (Data : VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Item : out Value) return Boolean;
   function Encode
     (Item : Value'Class)
      return VSS.Stream_Element_Vectors.Stream_Element_Vector;

   function Member
     (Item : Value'Class; Name : VSS.Strings.Virtual_String) return Value;
   --  Empty means absent or duplicate. Input must be parsed, valid JSON.
   function Is_Object (Item : Value'Class) return Boolean;
   function Is_String (Item : Value'Class) return Boolean;
   function Is_Integer (Item : Value'Class) return Boolean;
   function Is_Boolean (Item : Value'Class) return Boolean;
   function Is_Array (Item : Value'Class) return Boolean;
   function Text (Item : Value'Class) return VSS.Strings.Virtual_String;
   function Text
     (Item : Value'Class; Name : VSS.Strings.Virtual_String)
      return VSS.Strings.Virtual_String;
   function Element (List : Value'Class; Index : Positive) return Value;

   function Object_Value return Value;
   function Array_Value return Value;
   function String_Value (Item : VSS.Strings.Virtual_String) return Value;
   function Integer_Value (Item : ACP.Types.Integer_64) return Value;
   function Null_Value return Value;
   procedure Add
     (Object : in out Value'Class;
      Name   : VSS.Strings.Virtual_String;
      Item   : Value'Class);
   procedure Append (List : in out Value'Class; Item : Value'Class);

   function Request
     (Identifier : Value; Method : VSS.Strings.Virtual_String; Params : Value)
      return Value;
   function Response (Identifier : Value; Result : Value) return Value;
   function Error_Response
     (Identifier : Value;
      Code       : ACP.Types.Integer_64;
      Message    : VSS.Strings.Virtual_String;
      Data       : Value := Object_Value) return Value;
   function Parse (Text : String) return Value;
   function Encode (Item : Value'Class) return String;
   function Get (Item : Value'Class; Name : String) return Value;
   function To_JSON_String (Text : String) return Value;
   function To_JSON_Integer (Number : Long_Long_Integer) return Value;
   function To_JSON_Number (Number : Long_Float) return Value;
   function To_JSON_Boolean (Flag : Boolean) return Value;
   function Get_Text (Item : Value'Class; Name : String := "") return String;
   function Get_Integer
     (Item    : Value'Class;
      Name    : String := "";
      Default : Long_Long_Integer := 0) return Long_Long_Integer;
   function Get_Number
     (Item : Value'Class; Name : String := ""; Default : Long_Float := 0.0)
      return Long_Float;
   function Get_Boolean
     (Item : Value'Class; Name : String := ""; Default : Boolean := False)
      return Boolean;
   function Length (List : Value'Class) return Natural;
   type Field is record
      Name : VSS.Strings.Virtual_String;
      Item : Value;
   end record;
   type Field_Array is array (Positive range <>) of Field;
   function Make_Object (Fields : Field_Array) return Value;
   type Value_Array is array (Positive range <>) of Value;
   function Make_Array (Items : Value_Array) return Value;
   procedure Put (Item : in out Value; Name : String; Data : Value);
   function Member_Names (Item : Value) return Value;
end Ambient.JSON;
