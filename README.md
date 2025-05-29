This repository contains an implementation of Lua preprocessor written fully in Figura Lua.

Example of simple, one-sided setup can be found in `init.lua`.

## Annotations
This is a table of annotations implemented so far.
|Annotation |Description       |Syntax                         |
|-----------|------------------|-------------------------------|
|`define`|Defines a keyword. After definition, this keyword will be replaced with `[VALUE]`, or empty char sequence if it has no value.|`--!define (NAME) [VALUE]`|
|`undefine`|Undefines a keyword.|`--!undefine (NAME)`|
|`macro`|Defines a macro. After definition, macro will be replaced with specified expression. If macro definition is invalid, it will be defined as a normal keyword.|`--!macro (NAME) [arg1, arg2, arg3...]; (EXPRESSION)`|
|`ifequal`|Conditional annotation which's condition is two defines, two literals, or define and a literal having the same value.|`--!ifequal (literal\|define) (literal\|define)`|
|`ifnotequal`|Conditional annotation which's condition is two defines, two literals, or define and a literal NOT having the same value.|`--!ifnotequal (literal\|define) (literal\|define)`|
|`ifdef`|Conditional annotation which's condition is keyword with specified name being defined. Must be closed with `--!else` or `--!endif` annotation.|`--!ifdef (NAME)`|
|`ifndef`|Conditional annotation which's condition is keyword with specified name being undefined. Must be closed with `--!else` or `--!endif` annotation.|`--!ifndef (NAME)`|
|`else`|Conditional annotation that can work only in pair with another conditional annotation. It can also continue the chain of conditional annotations.|`--!else [CONDITIONAL_ANNOTATION_NAME (args)]`|
|`endif`|Closes conditional annotation(s) chain|`--!endif`|
|`info`|Tells preprocessor to log info|`--!info (message)`|
|`warning`|Tells preprocessor to log a warning|`--!warning (message)`|
|`error`|Tells preprocessor to throw an error. Error will contain name of the script, line and column, and also an error message|`--!error (message)`|

## Setup
In order to work, this preprocessor requires some setup, such as:
* Figura's script optimization must be disabled, fully.
* `preprocessor.lua` and `reader.lua` scripts must be in the root folder of the avatar. `preprocessor.lua` is a script of preprocessor itself, and `reader.lua` is a token reader used by this preprocessor. To save some space, they later can be excluded from avatar with `preproc.excludeScript("script")`.
* Initialization script. For easy setup, it must be the only script specified in `avatar.json`'s `autoScripts`. Example of initialization script can be found in this repo, with name `init.lua`.

This is already enough for a basic setup. For more complex and customizable setup you can use other methods in the preprocessor init script.

## Methods
|Function|Description|
|--------|-----------|
|`preproc.setEntrypoint(name?: string)`|Sets the entry point of an avatar. By default it is set to the name of the first autoscript in the avatar. On the final steps of preprocessing, preprocessor will replace the script with specified name with short entrypoint script, which will run all the scripts added with `preproc.addAutoscript`. Setting `name` argument to `nil` will disable entrypoint creation.|
|`preproc.addAutoscript(name: string)`|Adds script with specified name to the autoscripts. It also worth mentioning that autoscripts that were added first will also be preprocessed earlier than all other scripts.|
|`preproc.excludeScript(name: string)`|Excludes script from the avatar, and from preprocessing as well.|
|`preproc.enableDebug(internal?: bool)`|Enables debug output. Passing no arguments to the function will enable regular level debugging, passing true will enable `INTERNAL` level debug output, and passing `false` will disable debug output.|
|`preproc.define(name: string, value?: string)`|Defines a keyword. Works the same way as `--!define` annotation.|
|`preproc.macro(name: string, macro: string\|func(...: string...) -> string)`|Defines a macro. String definition works the same way as `--!macro` annotation, while passing a function as a `macro` argument allows definition of more complex macros, but only on init stage of preprocessing.|
|`preproc.undefine(name: string)`| Works the same way as `--!undefine annotation`|
|`preproc.runAfterPreprocess()`|Tells preprocessor to automatically run the entrypoint script after preprocessing is finished. Will not have any effect if entrypoint is not set.|
|`preproc.optimization(level: integer)`|Sets the optimization level for the scripts. 0 - no optimization, 1 - removing comments, 2 - full optimization, removing all the comments and unnecessary whitespaces.|
|`preproc.preprocessScript(name: string, content: string)`|Runs the script preprocessing and returns preprocessed output. Might be useful for more complex initialization setups or double-sided setups.|
|`preproc.reset()`|Fully resets the state of the preprocessor.|
|`preproc.setScriptAcceptor(acceptor: func(name: string, contents?: string))`|Sets the script acceptor which preprocessor will call after preprocessing the script. `contents` argument being nil means script should be removed.|
|`preproc.setEntrypointGenerator(generator: func(autoscripts: [string]) -> string)`|Sets the entrypoint generator for the preprocessor. Preprocessor will call it during generation of entrypoint script generation.|
|`preproc.run()`|Runs the preprocessor, preprocessing all the non-excluded scripts in the avatar.|

## Additional notes
* On the start of preprocessing, the empty keyword `__PREPROCESSED__` is defined.
* On preprocessor initialization (require), macro `STRINGIFY(name: string)` is defined. It is a special macro that returns contents of specified DEFINE (not macro) as a string representation.
* For complex macros definition you must create a function that returns a string and takes arguments you need also as a strings. (yes they are called complex only because they can do more than just paste expressions in the code)
