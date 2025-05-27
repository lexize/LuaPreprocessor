--!ifndef __PREPROCESSED__
error("This script MUST be run with preprocessor. See [link to preprocessor]");
--!endif

print(__LINE__); --> 1
print(__COLUMN__, __LINE__);
print(STRINGIFY(__SCRIPT__)); --> "test" 

--!define NYA
--!ifdef __HOST__
--!define FOO mrrp meow
function meow()
   return "awa"
end
--!else
--!define FOO mrawrmrwu
function meow()
   error()
end 

--!ifdef NYA
print("I will be here only if NYA is defined and __HOST__ is not")
--!endif

--!endif
--!macro BAR a, b, c; ((a) + (b)) * (c)

print(STRINGIFY(FOO)); --> IFDEF __HOST__: "mrrp meow" ELSE: "mrawrmrwu"
print(BAR(2, 4, 6)); --> 36
print(meow()); --> IFDEF __HOST__: "awa" ELSE: error
