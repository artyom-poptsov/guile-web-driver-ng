(define-module (web driver key)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1))

(define-public (key->unicode-char code)
  (if (equal? 1 (string-length code))
      code
      (first
        (find
          (match-lambda ((char key-code) (string-ci=? key-code code)))
          char-key-codes))))

; Mappings between single unicode character and keyevent codes
; Copy Pasted from the specification page
; ttps://w3c.github.io/webdriver/

(define char-key-codes
  ; normalized key value table
  '(("\uE001" "Cancel")
    ("\uE002" "Help")
    ("\uE003" "Backspace")
    ("\uE004" "Tab")
    ("\uE005" "Clear")
    ("\uE006" "Return")
    ("\uE007" "Enter")
    ("\uE008" "Shift")
    ("\uE009" "Control")
    ("\uE00A" "Alt")
    ("\uE00B" "Pause")
    ("\uE00C" "Escape")
    ("\uE00D" " ")
    ("\uE00E" "PageUp")
    ("\uE00F" "PageDown")
    ("\uE010" "End")
    ("\uE011" "Home")
    ("\uE012" "ArrowLeft")
    ("\uE013" "ArrowUp")
    ("\uE014" "ArrowRight")
    ("\uE015" "ArrowDown")
    ("\uE016" "Insert")
    ("\uE017" "Delete")
    ("\uE018" ";")
    ("\uE019" "=")
    ("\uE01A" "0")
    ("\uE01B" "1")
    ("\uE01C" "2")
    ("\uE01D" "3")
    ("\uE01E" "4")
    ("\uE01F" "5")
    ("\uE020" "6")
    ("\uE021" "7")
    ("\uE022" "8")
    ("\uE023" "9")
    ("\uE024" "*")
    ("\uE025" "+")
    ("\uE026" ",")
    ("\uE027" "-")
    ("\uE028" ".")
    ("\uE029" "/")
    ("\uE031" "F1")
    ("\uE032" "F2")
    ("\uE033" "F3")
    ("\uE034" "F4")
    ("\uE035" "F5")
    ("\uE036" "F6")
    ("\uE037" "F7")
    ("\uE038" "F8")
    ("\uE039" "F9")
    ("\uE03A" "F10")
    ("\uE03B" "F11")
    ("\uE03C" "F12")
    ("\uE03D" "Meta")
    ("\uE040" "ZenkakuHankaku")
    ("\uE050" "Shift")
    ("\uE051" "Control")
    ("\uE052" "Alt")
    ("\uE053" "Meta")
    ("\uE054" "PageUp")
    ("\uE055" "PageDown")
    ("\uE056" "End")
    ("\uE057" "Home")
    ("\uE058" "ArrowLeft")
    ("\uE059" "ArrowUp")
    ("\uE05A" "ArrowRight")
    ("\uE05B" "ArrowDown")
    ("\uE05C" "Insert")
    ("\uE05D" "Delete")
 
    ; Shifted character table
    ("`"	"Backquote")
    ("\\"	"Backslash")
    ("\uE003"   "Backspace")
    ("["	"BracketLeft")
    ("]"	"BracketRight")
    (","	"Comma")
    ("0"	"Digit0")
    ("1"	"Digit1")
    ("2"	"Digit2")
    ("3"	"Digit3")
    ("4"	"Digit4")
    ("5"	"Digit5")
    ("6"	"Digit6")
    ("7"	"Digit7")
    ("8"	"Digit8")
    ("9"	"Digit9")
    ("="	"Equal")
    ("<"	"IntlBackslash")
    ("a"	"KeyA")
    ("b"	"KeyB")
    ("c"	"KeyC")
    ("d"	"KeyD")
    ("e"	"KeyE")
    ("f"	"KeyF")
    ("g"	"KeyG")
    ("h"	"KeyH")
    ("i"	"KeyI")
    ("j"	"KeyJ")
    ("k"	"KeyK")
    ("l"	"KeyL")
    ("m"	"KeyM")
    ("n"	"KeyN")
    ("o"	"KeyO")
    ("p"	"KeyP")
    ("q"	"KeyQ")
    ("r"	"KeyR")
    ("s"	"KeyS")
    ("t"	"KeyT")
    ("u"	"KeyU")
    ("v"	"KeyV")
    ("w"	"KeyW")
    ("x"	"KeyX")
    ("y"	"KeyY")
    ("z"	"KeyZ")
    ("-"	"Minus")
    ("."	"Period")
    ("'"	"Quote")
    (";"	"Semicolon")
    ("/"	"Slash")
    ("\uE00A"	"AltLeft")
    ("\uE052"	"AltRight")
    ("\uE009"	"ControlLeft")
    ("\uE051"	"ControlRight")
    ("\uE006"	"Enter")
    ("\uE03D"	"OSLeft")
    ("\uE053"	"OSRight")
    ("\uE008"	"ShiftLeft")
    ("\uE050"	"ShiftRight")
    (" " 	"Space")
    ("\uE004"	"Tab")
    ("\uE017"	"Delete")
    ("\uE010"	"End")
    ("\uE002"	"Help")
    ("\uE011"	"Home")
    ("\uE016"	"Insert")
    ("\uE00F"	"PageDown")
    ("\uE00E"	"PageUp")
    ("\uE015"	"ArrowDown")
    ("\uE012"	"ArrowLeft")
    ("\uE014"	"ArrowRight")
    ("\uE013"	"ArrowUp")
    ("\uE00C"	"Escape")
    ("\uE031"	"F1")
    ("\uE032"	"F2")
    ("\uE033"	"F3")
    ("\uE034"	"F4")
    ("\uE035"	"F5")
    ("\uE036"	"F6")
    ("\uE037"	"F7")
    ("\uE038"	"F8")
    ("\uE039"	"F9")
    ("\uE03A"	"F10")
    ("\uE03B"	"F11")
    ("\uE03C"	"F12")
    ("\uE01A"	"Numpad0")
    ("\uE01B"	"Numpad1")
    ("\uE01C"	"Numpad2")
    ("\uE01D"	"Numpad3")
    ("\uE01E"	"Numpad4")
    ("\uE01F"	"Numpad5")
    ("\uE020"	"Numpad6")
    ("\uE021"	"Numpad7")
    ("\uE022"	"Numpad8")
    ("\uE023"	"Numpad9")
    ("\uE025"	"NumpadAdd")
    ("\uE026"	"NumpadComma")
    ("\uE028"	"NumpadDecimal")
    ("\uE029"	"NumpadDivide")
    ("\uE007"	"NumpadEnter")
    ("\uE024"	"NumpadMultiply")
    ("\uE027"	"NumpadSubtract")))
