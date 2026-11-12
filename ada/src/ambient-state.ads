with Ambient.JSON;
with VSS.Strings;

package Ambient.State is
   type Store is tagged limited private;
   procedure Open (Self : in out Store; Path : String);
   procedure Save (Self : Store);
   function Get (Self : Store; Key : String) return JSON.Value;
   procedure Set (Self : in out Store; Key : String; Item : JSON.Value);
   procedure Reset (Self : in out Store);
   function Contents (Self : Store) return JSON.Value;
   function File_Path (Self : Store) return String;
   function Memory_Index (Root : String) return JSON.Value;
   function Watches (Root : String) return JSON.Value;
   procedure Watch (Root : String; What : String; Remove : Boolean := False);
   procedure Remember (Root, Subject, Date_Text, Line : String);
   function Tail (Items : JSON.Value; Count : Natural) return JSON.Value;
private
   type Store is tagged limited record
      Path : VSS.Strings.Virtual_String;
      Data : JSON.Value := JSON.Object_Value;
   end record;
end Ambient.State;
