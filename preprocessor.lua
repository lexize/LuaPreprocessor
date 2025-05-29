-- Requiring the reader lib;
local reader = require("reader");

-- The library's root.
local preproc = {};
-- Defines, defined by the script, and preproc.define.
local defines = {};
-- Macros defined by the script, and preproc.macro.
local macros = {};
-- Autoscripts defined by the init script.
local autoscripts = {};
-- Entrypoint of the script.
local entrypoint = avatar:getNBT().metadata.autoScripts[1];
-- Should preprocessor call the entrypoint after preprocessing?
local runAfterPreproc = false;
-- Level of optimisation
local optimisationLevel = 0;
-- List of libs to remove after preprocessing
local excludedScripts = {};
-- Should preprocessor dump the info for debugging
local debugDump = false;
-- The script acceptor function
local scriptAcceptor = nil;
-- The entrypoint generator function
local entrypointGenerator = nil;

local currentScript = nil;

local log_colors = {
    INFO = "#55FF55",
    DEBUG = "#00AA00",
    WARNING = "#FFAA00",
    ERROR = "#FF5555",
    FATAL = "#FF0000"
}

---Log function
---@param message any
---@param level? "INFO"|"DEBUG"|"WARNING"|"ERROR"|"FATAL"
local function log(message, level, namespace)
    local level = (level or "INFO"):upper();
    if (level ~= "DEBUG" or debugDump) and (level ~= "INTERNAL" or debugDump == "INTERNAL") then
        local prefix;
        if namespace ~= nil and env ~= "___ROOT___" then
            prefix = level.." | "..namespace;
        else
            prefix = level;
        end
        local text = {text = ("[ %s ] "):format(prefix), color = log_colors[level] or log_colors.INFO, extra = { {text = message .. "\n", color = "white"} }};
        printJson(toJson(text));
    end
end

local function typeEq(val, tp)
   local typ = type(val);
   return typ == tp, typ;
end

local function typeOrError(val, tp)
   local res, typ = typeEq(val, tp);
   if not typeEq(val, tp) then
      error(("%s expected, got %s"):format(tp, typ));
   end
end

local function strBuf(str)
   local buf = data:createBuffer(#str);
   buf:writeByteArray(str);
   buf:setPosition(0);
   return buf;
end

local function indexOf(tbl, val) 
   for i, v in ipairs(tbl) do
      if v == val then return i end
   end
   return nil;
end

---Sets the name of the entry point.
---This is name of the file that will be used to initialize all the scripts.
---Name must match the name of current init script, so, the script running the preprocessor.
---To avoid unexpected results, this script, or script calling this script, must be the only script in avatar.json's autoScripts.
---Default name of entrypoint is init.
function preproc.setEntrypoint(name)
   if name == nil then
      entrypoint = nil;
      log("Disabling entrypoint", "DEBUG");
      return;
   end
   typeOrError(name, "string");
   entrypoint = name;
   log("Setting Entrypoint to \""..name..'"', "DEBUG");
end

---Adds the autoscript. Will be included as a require in entrypoint file.
---Also adds priority to the script, so autoscripts added first will be processed earlier.
function preproc.addAutoscript(name)
   typeOrError(name, "string")
   autoscripts[#autoscripts + 1] = name;
   log("Adding \"" .. name .. "\" to autoscripts", "DEBUG");
end

---Adds the script to be removed from avatar NBT. Excluded scripts are also excluded from preprocessing.
---Name has to be the exact name of the script in the avatar nbt.
---This function is useful for saving space by removing reader and preprocessor lib.
function preproc.excludeScript(name)
   typeOrError(name, "string");
   excludedScripts[name] = true;
   log("Excluding \"".. name .."\" from avatar.", "DEBUG");
end

function preproc.enableDebug(internal)
   if internal then
      debugDump = "INTERNAL";
      log("Internal level debug output enabled", "INTERNAL");
   elseif internal == false then
      debugDump = false;
   else
      debugDump = true;
      log("Debug output enabled", "DEBUG");
   end
end

---Defines a preprocessor variable
---If the value is not string, it will be converted to one by using tostring() function.
---If the value is nil, the empty string will be put into defines.
---@param name string
---@param value? string|any
function preproc.define(name, value, internal)
   typeOrError(name, "string");
   local tp = type(value);
   if tp == "nil" then 
      defines[name] = "";
   elseif tp ~= "string" then
      defines[name] = tostring(value);
      macros[name] = nil;
   else
      defines[name] = value;
      macros[name] = nil;
   end
   if tp == "nil" or value == "" then
      log("Defining "..name.." as empty define.", internal and "INTERNAL" or "DEBUG");
   else
      log("Defining "..name.." as \"" .. defines[name] .. "\"", internal and "INTERNAL" or "DEBUG");
   end
end

local __expand_macro;

---Defines a preprocessor macro
---If the macro argument is a function, macro will call this function and replace the macro with the first string return of the function. All the arguments provided to the function are raw string args
---If the macro argument is a string, macro will replace the literals with input values. If macro definition is invalid, it will add a define instead.
function preproc.macro(name, macro)
   typeOrError(name, "string");
   local tp = type(macro);
   if tp ~= "string" then
      typeOrError(macro, "function");
      macros[name] = macro;
      defines[name] = nil;
   else
      local annBuf = strBuf(macro);
      local args = {};
      local finished = false;
      while annBuf:available() > 0 do
         reader.skipWhitespaces(annBuf);
         local tp, argName = reader.readToken(annBuf);
         if tp ~= "literal" then error(("Argument name (literal) expected, got %s (%s)"):format(tp, argName)) end
         args[#args + 1] = argName;

         reader.skipWhitespaces(annBuf);
         local tp, token = reader.readToken(annBuf);
         if token == ";" then
            finished = true;
            break;
         elseif token ~= "," then
            break;
         end
      end
      if finished then
         reader.skipWhitespaces(annBuf);
         macro_def = annBuf:readByteArray();
         annBuf:close();
      else
         annBuf:close();
         goto __define__
      end
      
      macros[name] = __expand_macro(args, macro_def);
      defines[name] = nil;
      log("Defined macro \""..name.."\" as \""..macro..'"', "DEBUG");
   end

   goto __ret__
   
   ::__define__::
   preproc.define(name, macro);
   log("Invalid definition of macro "..name..", handling as simple define instead.", "WARNING");
   ::__ret__::
end

function preproc.undefine(name)
   typeOrError(name, "string");
   defines[name] = nil;
   macros[name] = nil;
   log("Undefined "..name, "DEBUG");
end

---Sets the flag to run the entrypoint after preprocessing.
function preproc.runAfterPreprocess()
   runAfterPreproc = true;
   log("Avatar init script will be run after preprocessing is finished.", "DEBUG");
end

---Sets the optimization level.
---0 - no optimization
---1 - removing comments
---2 - removing all the unneeded whitespaces and comments, replacing semicolons with spaces.
---Default optimisation level is 0.
function preproc.optimization(level) 
   typeOrError(level, "number");
   optimisationLevel = level;
   log("Setting optimization level to "..level, "DEBUG");
end

local __read_args;

local currentCtx;

local function updateLineAndColumn(buf, startPos)
   local pos = buf:getPosition();
   if pos > startPos then
      local diff = startPos - currentCtx.prevPos;
      buf:setPosition(currentCtx.prevPos);
      local str = buf:readByteArray(diff);
      for i = 1, diff, 1 do 
         local s = str:sub(i, i);
         if s ~= "\n" then
            currentCtx.column = currentCtx.column + 1;
         else
            currentCtx.column = 1;
            currentCtx.line = currentCtx.line + 1;
         end
      end
      preproc.define("__LINE__", currentCtx.line, true);
      preproc.define("__COLUMN__", currentCtx.column, true);
      currentCtx.prevPos = startPos;
   end
   buf:setPosition(pos);
end

local function processMacro(val, buf, startPos)
   if val == "__LINE__" or val == "__COLUMN__" then
      updateLineAndColumn(buf, startPos);
   end
   local rep = defines[val] or macros[val];
   local typ = type(rep);
   if rep ~= nil then
      if typ == "string" then
         return rep;
      elseif typ == "function" then
         local args = __read_args(buf);
         if args ~= nil then
            return rep(table.unpack(args)) or "";
         end
      end
   else
      return val;
   end
end

local annotations;

local function isAnnotation(tp, val)
   return (tp == "comment" or tp == "multiline_comment") and val:sub(1, 1) == "!";
end

local function readAnnotation(commentText)
   local annBuf = strBuf(commentText);
   annBuf:read();
   local tp, src, val = reader.readToken(annBuf);
   if tp ~= "literal" then
      annBuf:close();
      return nil;
   elseif tp == "literal" and annotations[val] ~= nil then
      local fun = annotations[val];
      local p = annBuf:getPosition();
      local t = reader.readToken(annBuf); -- Reading one token to remove whitespace;
      if t ~= "whitespace" then
         annBuf:setPosition(p);
      end
      return val, annBuf, fun;
   end
end

local conditionals;

local function processConditionalAnnotation(srcBuf, cond, exec)
   local tp, src, val;
   local tokenPos = 0;
   local prevPos = 0;
   local out = "";
   repeat
      tokenPos = srcBuf:getPosition();
      tp, src, val = reader.readToken(srcBuf);
      if tp == nil then
         error("Conditional annotations must be either closed with --!endif or continued by --!else, but EOF was found.");
      elseif isAnnotation(tp, val) then
         updateLineAndColumn(srcBuf, tokenPos);
         local ann, annBuf, func = readAnnotation(val);
         if ann == "endif" then
            return out;
         elseif not conditionals[ann] or ann ~= "else" then
            local v = (func(annBuf, srcBuf, exec) or "");
            if exec then
               out = out .. v;
            end
         elseif ann == "else" then
            local v = (func(annBuf, srcBuf, exec and not cond, true) or "");
            return out .. (exec and v or "");
         end
      elseif tp == "literal" and exec and cond then
         out = out .. processMacro(val, srcBuf, prevPos);
      else
         if exec and cond then
            out = out .. src;
         end
      end
      prevPos = tokenPos;
   until false
end

local function ifEqualAnnotation(annBuf, srcBuf, exec)
   local cond = exec or false;
   if exec then
      reader.skipWhitespaces(annBuf);
      local tp1, arg1, arg1Val = reader.readToken(annBuf);
      if tp1 == "literal" then
         arg1Val = defines[arg1];
      elseif tp1 == nil then
         error("Define or a literal expected, but no argument were provided");
      end
      reader.expectType("whitespace", annBuf);
      local tp2, arg2, arg2Val = reader.readToken(annBuf);
      if tp2 == "literal" then
         arg2Val = defines[arg2];
      elseif tp2 == nil then
         error("Define or a literal expected as a second argument, but not argument were provided")
      end     cond = arg1Val == arg2Val;
   end

   return processConditionalAnnotation(srcBuf, cond, exec);
end

local function ifNEqualAnnotation(annBuf, srcBuf, exec)
   local cond = exec or false;
   if exec then
      reader.skipWhitespaces(annBuf);
      local tp1, arg1, arg1Val = reader.readToken(annBuf);
      if tp1 == "literal" then
         arg1Val = defines[arg1];
      elseif tp1 == nil then
         error("Define or a literal expected, but no argument were provided");
      end
      reader.expectType("whitespace", annBuf);
      local tp2, arg2, arg2Val = reader.readToken(annBuf);
      if tp2 == "literal" then
         arg2Val = defines[arg2];
      elseif tp2 == nil then
         error("Define or a literal expected as a second argument, but not argument were provided")
      end

      cond = arg1Val ~= arg2Val;
   end

   return processConditionalAnnotation(srcBuf, cond, exec);
end

local function ifDefAnnotation(annBuf, srcBuf, exec)
   local tp, src, name = reader.readToken(annBuf);
   if tp == "literal" then
      local cond = exec and defines[name] ~= nil;
      return processConditionalAnnotation(srcBuf, cond, exec);
   else
      error(("Expected name of the define, got %s"):format(tp))
   end
end

local function ifNDefAnnotation(annBuf, srcBuf, exec)
   local tp, src, name = reader.readToken(annBuf);
   if tp == "literal" then
      local cond = exec and defines[name] == nil;
      return processConditionalAnnotation(srcBuf, cond, exec);
   else
      error(("Expected name of the define, got %s"):format(tp))
   end
end

local function elseAnnotation(annBuf, srcBuf, exec, valid)
   local tp, src, name = reader.readToken(annBuf);
   if tp == nil or tp ~= "literal" then
      return processConditionalAnnotation(srcBuf, true, exec);
   else
      local a = conditionals[name];
      if name ~= "else" and a ~= nil then
         reader.skipWhitespaces(annBuf);
         return a(annBuf, srcBuf, exec);
      else
         error(("--!else must be either followed by a name of other conditional annotation and it's arguments, or followed by whitespace or linebreak, but, got %s instead"):format(tp));
      end
   end
end

local function endIfAnnotation(annBuf, _, exec)
   if not exec then return end
   error("--!endif annotation must be used only with conditional annotations, but, no opening conditional annotations was found.")
end

local function defineAnnotation(annBuf, _, exec)
   if not exec then return end
   reader.skipWhitespaces(annBuf);
   local tp, name = reader.readToken(annBuf);
   if tp ~= "literal" then error(("Expected define name (literal), got %s"):format(tp)) end
   reader.skipWhitespaces(annBuf);
   value = annBuf:readByteArray();

   preproc.define(name, value);
end

local function undefineAnnotation(annBuf, _, exec)
   if not exec then return end
   reader.skipWhitespaces(annBuf);
   local tp, name = reader.readToken(annBuf);
   if tp ~= "literal" then error(("Expected define name (literal), got %s"):format(tp)) end
   
   preproc.undefine(name);
end

local function macroAnnotation(annBuf, _, exec)
   if not exec then return end
   
   reader.skipWhitespaces(annBuf);
   local tp, name = reader.readToken(annBuf);
   if tp ~= "literal" then error(("Macro name (literal) expected, got %s"):format(tp)) end 
   
   reader.skipWhitespaces(annBuf);
   local macroDefString = annBuf:readByteArray();
   preproc.macro(name, macroDefString);
end

local function infoAnnotation(annBuf, _, exec) 
   if not exec then return end
   reader.skipWhitespaces(annBuf);
   local msg = annBuf:readByteArray();
   log(msg, "INFO", currentScript);
end

local function warningAnnotation(annBuf, _, exec)
   if not exec then return end
   reader.skipWhitespaces(annBuf);
   local msg = annBuf:readByteArray();
   log(msg, "WARNING", currentScript);
end

local function errorAnnotation(annBuf, srcBuf, exec)
   if not exec then return end
   reader.skipWhitespaces(annBuf);
   local msg = annBuf:readByteArray();
   log(("Preprocessing error in script §a%s§r at §a%s§r:§a%s"):format(currentScript, currentCtx.line, currentCtx.column), "ERROR", currentScript);
   log(msg, "ERROR", currentScript)
   error("Preprocessing error");
end

annotations = {
   ["define"] = defineAnnotation,
   ["undefine"] = undefineAnnotation,
   ["macro"] = macroAnnotation,
   ["ifequal"] = ifEqualAnnotation,
   ["ifnotequal"] = ifNEqualAnnotation,
   ["ifdef"] = ifDefAnnotation,
   ["ifndef"] = ifNDefAnnotation,
   ["else"] = elseAnnotation,
   ["endif"] = endIfAnnotation,
   ["info"] = infoAnnotation,
   ["warning"] = warningAnnotation,
   ["error"] = errorAnnotation
}

conditionals = {
   ["ifequal"] = ifEqualAnnotation,
   ["ifnotequal"] = ifNEqualAnnotation, 
   ["ifdef"] = ifDefAnnotation,
   ["ifndef"] = ifNDefAnnotation,
   ["else"] = elseAnnotation,
   ["endif"] = endIfAnnotation,
}

function preproc.preprocessScript(name, content)
   log("Starting to process script \""..name.."\"", "DEBUG");
   preproc.define("__SCRIPT__", name);
   currentScript = name;
   local ctx = {
      line = 1,
      column = 1,
      prevPos = 0
   }
   currentCtx = ctx;
   local buf = strBuf(content);
   local out = "";
   local tokenPos;
   local prevPos = 0; 
   repeat
      tokenPos = buf:getPosition();
      local tp, source, val = reader.readToken(buf);
      if tp == nil then
         break
      elseif isAnnotation(tp, val) then
         updateLineAndColumn(buf, tokenPos);
         local ann, annBuf, func = readAnnotation(val);
         if ann then
            addition = func(annBuf, buf, true);
            annBuf:close();
            out = out .. (addition or "");
         else
            out = out .. source;
         end
      elseif tp == "literal" then
         out = out .. processMacro(val, buf, prevPos);
      else
         out = out .. source;
      end
      prevPos = tokenPos;
   until false
   if optimisationLevel > 0 then
      log("Optimizing output of script \""..name..'"', "DEBUG");
      local newOut = "";
      buf:clear();
      buf:writeByteArray(out);
      buf:setPosition(0);
      repeat
         local tp, source = reader.readToken(buf);
         if tp == nil then break
         elseif tp == "whitespace" and optimisationLevel >= 2 then
            newOut = newOut .. " ";
         elseif (tp == "comment" or tp == "multiline_comment") and optimisationLevel >=1 then
            -- Do nothing, not adding anything to the source
         else
            newOut = newOut .. source;
         end
      until false
      out = newOut;
   end
   buf:close();
   currentCtx = nil;
   currentScript = nil;
   return out;
end

---Resets the state of the preprocessor.
function preproc.reset()
   defines = {};
   macros = {};
   autoscripts = {};
   entrypoint = avatar:getNBT().metadata.autoScripts[1];
   runAfterPreproc = false;
   optimisationLevel = 0;
   excludedScripts = {};
   debugDump = false;
   scriptAcceptor = nil;
   entrypointGenerator = nil;

   preproc.macro("STRINGIFY", function (def)
      local v = defines[def];
      if v == nil then return '""';
      else return '"'..v..'"'; end
   end)
end

---Setting the script acceptor of the preprocessor.
function preproc.setScriptAcceptor(acceptor)
   if acceptor == nil then
      scriptAcceptor = nil;
      log("Setting script acceptor to default one.", "DEBUG");
   else
      typeOrError(acceptor, "function");
      scriptAcceptor = acceptor;
      log("Changed script acceptor.", "DEBUG");
   end
end

---Setting the entrypoint generator of the preprocessor.
function preproc.setEntrypointGenerator(generator)
   if generator == nil then
      entrypointGenerator = nil;
      log("Resetting entrypoint generator to default one.", "DEBUG");
   else
      typeOrError(generator, "function");
      entrypointGenerator = generator;
      log("Changed entrypoint generator.", "DEBUG");
   end
end

---Runs the preprocessor
function preproc.run()
   preproc.define("__PREPROCESSED__");
   local scripts = getScripts();
   local processed = {}
   for _, v in ipairs(autoscripts) do
      if scripts[v] then
         processed[v] = preproc.preprocessScript(v, scripts[v]);
      end
   end
   
   if debugDump then file:mkdir("__preprocDebug"); end

   local acceptScript = scriptAcceptor or addScript;

   for k, scriptContent in pairs(scripts) do
      if excludedScripts[k] then
         acceptScript(k, nil);
      elseif k ~= entrypoint then
         if not processed[k] then
            processed[k] = preproc.preprocessScript(k, scriptContent);
         end
         if debugDump then file:writeString(("__preprocDebug/%s.lua"):format(k), processed[k]); end
         acceptScript(k, processed[k]);
      end
   end

   if entrypoint then
      local init_script_contents;
      if not entrypointGenerator then
         init_script_contents = "";
         for _, v in ipairs(autoscripts) do
            init_script_contents = init_script_contents .. ("require '%s'\n"):format(v);
         end
      else
         init_script_contents = entrypointGenerator(autoscripts);
      end

      acceptScript(entrypoint, init_script_contents);
      if runAfterPreproc then
         local f, err = loadstring(init_script_contents, entrypoint);
         if not f then error(err) end
         f();
      end
   end
end

local function __readRoundBrackets(buf)
   local start_pos = buf:getPosition();
   local src = "(";
   repeat
      local tp, source, val = reader.readToken(buf);
      if tp == nil then
         goto __error__
      elseif tp == "operator" then
         if val == "(" then
            local b = __readRoundBrackets(buf);
            if b == nil then goto __error__ end
            src = src .. b;
         elseif val == ")" then
            src = src .. val
            goto __ret_val__
         else
            src = src .. val;
         end
      else
         src = src .. source;
      end
   until false;

   ::__error__::
   src = nil;
   buf:setPosition(start_pos);
   
   ::__ret_val__::
   return src;
end

__read_args = function(buf, plain)
   local pos = buf:getPosition();
   ::read_start::
   local args = {""};
   local waiting_for_comma = false;
   local prev_pos = pos; 
   local tp, source, val = reader.readToken(buf);
   if tp == "whitespace" then
      goto read_start
   elseif tp ~= "operator" and val ~= "(" then
      goto __error__
   end
 
   repeat
      tp, source, val = reader.readToken(buf);
      if tp == "whitespace" then
         if not plain then
            local arg = args[#args];
            args[#args] = arg .. source;
         end
         goto __continue__
      elseif tp == "operator" then
         if val == "," then
            args[#args + 1] = "";
            waiting_for_comma = false;
            reader.skipWhitespaces(buf);
         elseif val == ")" then
            goto __ret_args__
         else
            if plain or waiting_for_comma then
               goto __error__
            elseif val == "(" then
               local v = __readRoundBrackets(buf);
               if v == nil then goto __error__ end
               local arg = args[#args];
               args[#args] = arg .. v;
            else
               local arg = args[#args];
               args[#args] = arg .. source;
            end
         end
      else
         if tp == nil or waiting_for_comma or (tp ~= "literal" and plain) then
            goto __error__
         else
            if plain then
               args[#args] = source;
               waiting_for_comma = true;
            else
               local arg = args[#args]
               args[#args] = arg .. source;
            end
         end
      end
      ::__continue__::
      prev_pos = buf:getPosition();
   until false
   
   ::__error__::
   buf:setPosition(pos);
   args = nil;

   ::__ret_args__::
   return args;
end

__expand_macro = function(args, macroContent)
   local elems = {""};
   local content = strBuf(macroContent);
   repeat
      local elem;
      local tp, src, val = reader.readToken(content);
      if tp == "literal" then
         local ind = indexOf(args, val);
         if ind then
            elems[#elems + 1] = ind;
            elems[#elems + 1] = "";
            goto __continue__
         end
      elseif tp == nil then
         local i = #elems;
         if #elems[i] == 0 then elems[i] = nil end
         break;
      end

      elem = elems[#elems];
      elems[#elems] = elem .. src;
      ::__continue__::
   until false

   content:close();
   
   return function(...)
      local mArgs = {...};
      local buf = "";
      for _, elem in ipairs(elems) do
         local tp = type(elem);
         if tp == "number" then
            buf = buf .. mArgs[elem];
         else
            buf = buf .. elem;
         end
      end
      return buf
   end
end

preproc.reset();

return preproc;
