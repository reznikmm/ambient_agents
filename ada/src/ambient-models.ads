with Chat_Completions_API.Types;
with Ambient.JSON;

package Ambient.Models is
   function Available return Boolean;
   function Post (URL, Token : String; Data : JSON.Value) return JSON.Value;
   function Complete
     (Messages :
        Chat_Completions_API.Types.ChatCompletionRequestMessage_Vector;
      Tools    : Chat_Completions_API.Types.ChatCompletionTool_Vector := [];
      Model    : String := "")
      return Chat_Completions_API.Types.ChatCompletionResponseMessage;
   function Structured
     (Instructions, Prompt : String; Model : String := "") return JSON.Value;
end Ambient.Models;
