local scripts_data = avatar:getNBT().scripts;

---@param name string
---@return string? Script contents
function readLocalScript(name)
   local path = name:gsub("%\\", ".");
   local script_data = scripts_data[name];
   if (not script_data) then return end
   local buffer = data:createBuffer(#script_data);
   for i = 1, #script_data, 1 do
      buffer:write(script_data[i]);
   end
   buffer:setPosition(0);
   local script = buffer:readString();
   buffer:close();
   return script;
end

function string.startsWith(self, start)
   local s = self:sub(1, #start);
   return s == start;
end

function string.endsWith(self, ending)
   local s = self:sub(#self-#ending);
   return s == ending;
end

local function readChar(buf, len)
   if len == nil then
      len = 1
   end
   return buf:readByteArray(len);
end

local escaping_table = {
   ["a"] = "\a", ["b"] = "\b", ["f"] = "\f", ["n"] = "\n",
   ["r"] = "\r", ["t"] = "\t", ["v"] = "\v", ["\\"] = "\\",
   ["'"] = "'", ['"'] = '"', ["\n"] = "\n"
}

local function readEscaping(buf)
   local source_buf = "";
   local char = readChar(buf);
   local codepoint = char:byte();
   source_buf = source_buf..char;
   if char == "z" then
      local e = false;
      repeat
         char = readChar(buf);
         local e = char:match("%S") ~= nil;
         if not e then source_buf = source_buf..char; end
      until e
      buf:setPosition(buf:getPosition()-1)
      return source_buf, "";
   elseif char == "x" then
      local seq = readChar(buf, 2);
      if #seq ~= 2 then error("Unexpected EOF"); end
      local chr = string.char(tonumber(seq, 16));
      source_buf = source_buf..seq;
      return source_buf, chr;
   elseif codepoint >= 48 and codepoint <= 57 then
      local val = codepoint - 48;
      local i = 0;
      repeat
         char = readChar(buf);
         codepoint = char:byte();
         if codepoint < 48 or codepoint > 57 then
            buf:setPosition(buf:getPosition()-1);
            break
         else
            val = (val * 10) + codepoint - 48;
         end
         source_buf = source_buf..char;
         i = i + 1;
      until i < 2
      return source_buf, string.char(val);
   elseif escaping_table[char] ~= nil then
      return source_buf, escaping_table[char]
   end
end

local function readString(closing)
   return function(start, buf)
      local source_buf = start;
      local string_buf = "";
      while true do
         local char = readChar(buf);
         if #char == 0 then error("Unexpected EOF") end
         source_buf = source_buf..char;
         if char == "\\" then 
            local source_add, string_add = readEscaping(buf);
            source_buf = source_buf..source_add;
            string_buf = string_buf..string_add;
         elseif char == closing then
            return "string", source_buf, string_buf;
         else
            string_buf = string_buf..char;
         end
      end
   end
end

local function readComment(start, buf)
   local source_buf = start;
   local comment_buf = "";
   local char;
   repeat
      char = readChar(buf)
      if char == "\n" then break end
      source_buf = source_buf .. char;
      comment_buf = comment_buf .. char;
   until #char == 0
   if #char == 1 then
      buf:setPosition(buf:getPosition() - 1);
   end
   return "comment", source_buf, comment_buf
end

local function readMultilineString(start, buf) 
   local reading_string = false;
   local level = 0;
   local source_buf = start;
   local string_buf = "";
   local closing_buf = "";
   local closing_level = 0;
   
   local first_newline = false;

   local char;
   repeat 
      char = readChar(buf);
      source_buf = source_buf .. char;
      if reading_string then
         if #closing_buf > 0 then
            if char == "=" then
               closing_buf = closing_buf .. char;
               closing_level = closing_level + 1;
               goto close
            elseif char == "]" then
               if closing_level == level then
                  return "multiline_string", source_buf, string_buf;
               else goto abort_closing end
            else goto abort_closing end
            ::abort_closing::
            string_buf = string_buf .. closing_buf;
            closing_level = 0;
            closing_buf = "";
            buf:setPosition(buf:getPosition() - 1);
            source_buf = source_buf:sub(1, -2);
            ::close::
         else
            if char == "]" then
               closing_buf = char;
            elseif not first_newline and char == "\n" and #string_buf == 0 then
               first_newline = true;
            else
               string_buf = string_buf .. char;
            end
         end
      else
         if char == "=" then
            level = level + 1;
         elseif char == "[" then
            reading_string = true;
         else break end
      end
   until #char == 0;
   
   return; -- Returning nil marks that this reader can't read the string
end

local function readMultilineComment(start, buf) 
   local tpe, src, val = readMultilineString(start, buf);
   if tpe ~= nil then
      return "multiline_comment", src, val
   end
end

local token_readers = {
   {"literal", "MATCH:^[_%w]+$"},
   {"whitespace", "MATCH:^%s+$"},
   {"multiline_comment", "--[", readMultilineComment},
   {"multiline_string", "[", readMultilineString},
   {"comment", "--", readComment},
   {"!operator",
      "+", "-", "*", "/", "%", "^", "#",
      "==", "~=", "<=", ">=", "<", ">", "=",
      "(", ")", "{", "}", "[", "]", "::",
      ";", ":", ",", "...", "..", "."
   },
   { "string", '"', readString('"') },
   { "string", "`", readString("'") },
   { "number", "MATCH:^%d+$" }
}

local reader = {};

---@param buf Buffer
---@return string type of token
---@return string source of token
---@return string value of token
function reader.readToken(buf)
   local reset_pos = buf:getPosition();
   for _, reader_desc in ipairs(token_readers) do
      local tpe = reader_desc[1];
      if string.startsWith(tpe, "!") then
         tpe = tpe:sub(2);
         for i = 2, #reader_desc, 1 do
            local m = reader_desc[i];
            local str = readChar(buf, #m);
            if str == m then
               return tpe, str, str;
            else
               buf:setPosition(reset_pos);
            end
         end
      else
         local action = reader_desc[2];
         local value; 
         if string.startsWith(action, "MATCH:") then
            local pat = action:sub(7);
            local content = "";
            local match;
            local eof = false;
            repeat 
               local char = readChar(buf);
               if #char == 0 then
                  eof = true;
                  break;
               end
               content = content .. char;
               match = content:match(pat);
            until match == nil;
            if eof then
               match = content:match(pat);
               if match then
                  return tpe, content, match;
               else
                  goto continue
               end
            else
               local content = content:sub(1, -2);
               buf:setPosition(buf:getPosition()-1);
               match = content:match(pat);
               if match then
                  return tpe, content, match;
               else
                  goto continue
               end
            end
         else
            local m = action;
            local str = readChar(buf, #m);
            if str == m then
               value = str;
            else
               goto continue
            end
         end
         local exec = reader_desc[3];
         if (type(exec) == "function") then
            local tp, src, val = exec(value, buf);
            if tp then
               return tp, src, val
            else
               goto continue
            end
         end
      end
      ::continue::
      buf:setPosition(reset_pos);
   end
end

function reader.expectType(tpe, buf)
   local tp = reader.readToken(buf);
   if tp ~= tpe then error(("Expected %s, got %s"):format(tpe, tp)); end
end

function reader.readType(tpe, src, buf)
   local tp, sr = reader.readToken(buf);
   return tp == tpe and sr == src;
end

function reader.readLiteralMatch(lit, buf)
   local tpe, source = reader.readToken(buf);
   return tpe == "literal" and source == lit;
end

function reader.readLiteral(buf)
   local tpe, source = reader.readToken(buf);
   if tpe == "literal" then return source end
end

function reader.skipWhitespaces(buf)
   local pos = buf:getPosition();
   local tpe = reader.readToken(buf);
   if tpe ~= "whitespace" then
      buf:setPosition(pos)
   end
end

function reader.readUntil(tpe, src, buf) 
   local reset_pos = buf:getPosition();
   local source = "";
   local tp, sr;
   repeat
      tp, sr = reader.readToken(buf);
      if tp == tpe and sr == src then
         buf:setPosition(reset_pos);
      elseif tp ~= nil then
         source = source .. sr;
         reset_pos = buf:getPosition();
      end
   until tp == tpe and sr == src or tp == nil
   return source;
end

return reader;
