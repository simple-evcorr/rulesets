" sample VIM syntax file for SEC (contributed by Alberto Corton)

if exists("b:current_syntax")
    finish
endif

let b:current_syntax = "sec"

syntax case ignore

syntax match ruleComment "^#.*$"

syntax match secVar '%\a\+'
syntax match ruleContextValue 'context\s*=\s*.\+'

syntax keyword secRule type time ptype desc continue pattern action context cfset
syntax keyword secRule constset rem ptype2 pattern2 desc2 context2 action2
syntax keyword secRule window thresh joincfset procallin

syntax keyword ruleType single singlewithscript singlewithsuppress pair 
syntax keyword ruleType pairwithwindow singlewiththreshold singlewith2thresholds 
syntax keyword ruleType eventgroup suppress calendar jump options 

syntax keyword rulePtype cached regexp
syntax keyword ruleContinue dontcont takenext
syntax keyword ruleContext SEC_STARTUP SEC_RESTART SEC_SOFTRESTART SEC_INTERNAL_EVENT SEC_LOGROTATE SEC_SHUTDOWN

syntax keyword ruleAction assign eval lcall logonly none write owritecl udgram 
syntax keyword ruleAction ustream udpsock tcpsock shellcmd spawn pipe create 
syntax keyword ruleAction delete obsolete set alias unalias add prepend fill
syntax keyword ruleAction report copy empty pop shift exists getsize getaliases
syntax keyword ruleAction getltime getctime setctime event tevent reset getwpos
syntax keyword ruleAction setwpos free call rewrite if else while break


highlight link secRule     Type
highlight link ruleComment Comment
highlight link ruleParam   Statement

highlight link ruleType     Constant
highlight link rulePtype    Constant
highlight link ruleContinue Constant
highlight link ruleContext  Identifier
highlight link ruleCfset    Identifier
highlight link ruleAction   PreProc
highlight link secVar       Special


highlight link ruleContextValue String
