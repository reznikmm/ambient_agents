with VSS.Strings;
with VSS.Stream_Element_Vectors;
with VSS.String_Vectors;

package Ambient.Support is
   function To_Virtual_String
     (Text : String) return VSS.Strings.Virtual_String;
   function To_UTF_8_String (Text : VSS.Strings.Virtual_String) return String;
   function Bytes
     (Text : String) return VSS.Stream_Element_Vectors.Stream_Element_Vector;
   function Text
     (Data : VSS.Stream_Element_Vectors.Stream_Element_Vector) return String;
   function Environment (Name : String; Default : String := "") return String;
   function Read_File (Path : String; Default : String := "") return String;
   procedure Write_File (Path : String; Content : String);
   procedure Append_File (Path : String; Content : String);
   function Inside (Root : String; Path : String) return String;
   function Slug (Text : String) return String;
   function Trim (Text : String) return String;
   function Image (Value : Long_Long_Integer) return String;
   function Contains (Text : String; Pattern : String) return Boolean;
   function Run
     (Program   : String;
      Arguments : VSS.String_Vectors.Virtual_String_Vector;
      Input     : String := "";
      Timeout   : Positive := 30) return String;
   procedure Log (Message : String);
end Ambient.Support;
