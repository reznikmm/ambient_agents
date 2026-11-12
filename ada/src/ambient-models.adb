with Ada.Strings.Fixed;
with Chat_Completions_API.Chats;
with Chat_Completions_API.HTTP_Requests;
with VSS.IRIs;
with VSS.Stream_Element_Vectors;
with VSS.Strings;
with Ambient.Support;

package body Ambient.Models is
   use Ambient.Support, Ambient.JSON;
   function Available return Boolean
   is (Environment ("CHAT_COMPLETIONS_URL") /= ""
       or Environment ("OPENAI_API_KEY") /= ""
       or Environment ("OPENROUTER_API_KEY") /= ""
       or Environment ("AI_GATEWAY_API_KEY") /= "");
   type HTTP_Handler is limited
     new Chat_Completions_API.HTTP_Requests.HTTP_Request
   with null record;
   overriding
   procedure Post
     (Self                        : in out HTTP_Handler;
      URL                         : VSS.IRIs.IRI;
      Content_Type, Authorization : VSS.Strings.Virtual_String;
      Output                      :
        VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Response                    :
        out VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Status_Code                 : out Natural);
   overriding
   procedure Post
     (Self                        : in out HTTP_Handler;
      URL                         : VSS.IRIs.IRI;
      Content_Type, Authorization : VSS.Strings.Virtual_String;
      Output                      :
        VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Response                    :
        out VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Status_Code                 : out Natural)
   is
      pragma Unreferenced (Self);
      --  curl provides TLS, chunked HTTP and timeouts. Credentials and payload
      --  travel through a private temporary input, never through command argv.
      Config : constant String :=
        "url = "
        & Encode (To_JSON_String (To_UTF_8_String (URL.To_Virtual_String)))
        & ASCII.LF
        & "header = "
        & Encode
            (To_JSON_String
               ("Content-Type: " & To_UTF_8_String (Content_Type)))
        & ASCII.LF
        & "header = "
        & Encode
            (To_JSON_String
               ("Authorization: " & To_UTF_8_String (Authorization)))
        & ASCII.LF
        & "data-binary = "
        & Encode (To_JSON_String (Text (Output)))
        & ASCII.LF;
      Raw    : constant String :=
        Run
          ("curl",
           ["--silent",
            "--show-error",
            "--max-time",
            "120",
            "--config",
            "-",
            "--write-out",
            To_Virtual_String (ASCII.LF & "%{http_code}")],
           Config,
           Timeout => 125);
      Split  : constant Natural :=
        Ada.Strings.Fixed.Index
          (Raw, String'(1 => ASCII.LF), Ada.Strings.Backward);
   begin
      if Split = 0 then
         raise Program_Error with "curl returned no HTTP status";
      end if;
      Status_Code := Natural'Value (Raw (Split + 1 .. Raw'Last));
      Response := Bytes (Raw (Raw'First .. Split - 1));
   end Post;
   function Post (URL, Token : String; Data : Value) return Value is
      HTTP     : HTTP_Handler;
      Response : VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Status   : Natural;
   begin
      HTTP.Post
        (VSS.IRIs.To_IRI (To_Virtual_String (URL)),
         "application/json",
         To_Virtual_String ("Bearer " & Token),
         Bytes (Encode (Data)),
         Response,
         Status);
      if Status not in 200 .. 299 then
         raise Program_Error
           with "HTTP " & Trim (Status'Image) & " from model provider";
      end if;
      return Parse (Text (Response));
   end Post;
   function Complete
     (Messages :
        Chat_Completions_API.Types.ChatCompletionRequestMessage_Vector;
      Tools    : Chat_Completions_API.Types.ChatCompletionTool_Vector := [];
      Model    : String := "")
      return Chat_Completions_API.Types.ChatCompletionResponseMessage
   is
      Server   : Chat_Completions_API.Server;
      HTTP     : aliased HTTP_Handler;
      Response : Chat_Completions_API.Types.CreateChatCompletionResponse;
      Success  : Boolean;
      Token    : constant String :=
        (if Environment ("OPENAI_API_KEY") /= ""
         then Environment ("OPENAI_API_KEY")
         elsif Environment ("OPENROUTER_API_KEY") /= ""
         then Environment ("OPENROUTER_API_KEY")
         else Environment ("AI_GATEWAY_API_KEY"));
      URL      : constant String :=
        Environment
          ("CHAT_COMPLETIONS_URL",
           (if Environment ("OPENROUTER_API_KEY") /= ""
            then "https://openrouter.ai/api/v1/chat/completions"
            elsif Environment ("AI_GATEWAY_API_KEY") /= ""
            then "https://ai-gateway.vercel.sh/v1/chat/completions"
            else "https://api.openai.com/v1/chat/completions"));
   begin
      if not Available then
         raise Program_Error
           with
             "set CHAT_COMPLETIONS_URL or an API key for chat/model workers";
      end if;
      Server.Set_Request_Handler (HTTP'Unchecked_Access);
      Server.Set_URL (To_Virtual_String (URL));
      Server.Set_API_Key (To_Virtual_String (Token));
      Chat_Completions_API.Chats.Chat
        (Server,
         To_Virtual_String
           (if Model = ""
            then Environment ("CHAT_MODEL", "local-model")
            else Model),
         Messages,
         Tools    => Tools,
         Response => Response,
         Success  => Success);
      if not Success or else Response.choices.Length = 0 then
         raise Program_Error
           with "Chat Completions request failed or returned no choices";
      end if;
      return Response.choices (1).message;
   end Complete;
   function Structured
     (Instructions, Prompt : String; Model : String := "") return Value
   is
      Response :
        constant Chat_Completions_API.Types.ChatCompletionResponseMessage :=
          Complete
            ([(role    => Chat_Completions_API.Types.system,
               content =>
                 To_Virtual_String
                   (Instructions
                    & ASCII.LF
                    & "Return only a JSON object, without Markdown fences."),
               others  => <>),
              (role    => Chat_Completions_API.Types.user,
               content => To_Virtual_String (Prompt),
               others  => <>)],
             Model => Model);
   begin
      return Parse (To_UTF_8_String (Response.content));
   end Structured;
end Ambient.Models;
