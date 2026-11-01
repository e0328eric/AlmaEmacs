;;; "Compiled" snippets and support files for `c-mode'  -*- lexical-binding:t -*-
;;; Snippet definitions:
;;;
(yas-define-snippets 'c-mode
					 '(("uni" "#include <unistd.h>" "unistd" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/unistd"
						nil nil)
					   ("union" "typedef union {\n        $0\n} ${1:name};"
						"union" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/union"
						nil nil)
					   ("strstr" "strstr(${1:string}, ${2:string});\n" "strstr"
						nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/strstr"
						nil nil)
					   ("str" "#include <string.h>" "string" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/string"
						nil nil)
					   ("std" "#include <stdlib.h>" "stdlib" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/stdlib"
						nil nil)
					   ("io" "#include <stdio.h>" "stdio" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/stdio"
						nil nil)
					   ("scanf"
						"scanf(\"${1:format string}\", ${2:&variable});\n"
						"scanf" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/scanf"
						nil nil)
					   ("pr" "printf(\"${1:format string}\"${2: ,a0,a1});"
						"printf" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/printf"
						nil nil)
					   ("packed" "__attribute__((__packed__))$0" "packed" nil
						nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/packed"
						nil nil)
					   ("malloc" "malloc(sizeof($1)${2: * ${3:3}});\n$0"
						"malloc" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/malloc"
						nil nil)
					   ("header" "#ifndef $1\n#define $1\n\n$0\n\n#endif // $1"
						"header" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/header"
						nil nil)
					   ("fprintf"
						"fprintf(${1:stdout}, \"${2:format string}\", ${3:variable});\n"
						"fprintf" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/fprintf"
						nil nil)
					   ("fgets" "fgets(${1:variable}, ${2:size}, ${3:stdin});\n"
						"fgets" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/fgets"
						nil nil)
					   ("compile"
						"// -*- compile-command: \"${1:gcc -Wall -o ${2:dest} ${3:file}}\" -*-"
						"compile" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/compile"
						nil nil)
					   ("ass" "#include <assert.h>\n$0" "assert" nil nil nil
						"/home/almagest/.config/emacs/.emacs.local/snippets/c-mode/assert"
						nil nil)))


;;; Do not edit! File generated at Thu Oct 29 17:45:23 2026
