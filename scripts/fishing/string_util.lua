local StringUtil = {}

---@param s string
---@param needle string
function StringUtil.starts_with(s, needle)
  if #s < #needle then
    return false
  end

  return s:sub(1, #needle) == needle
end

---@param s string
---@param needle string
function StringUtil.ends_with(s, needle)
  if #s < #needle then
    return false
  end

  return s:sub(#s - #needle + 1) == needle
end

---@param s string
---@param needle string
function StringUtil.strip_prefix(s, needle)
  if not StringUtil.starts_with(s, needle) then
    return s
  end

  return s:sub(#needle + 1)
end

---@param s string
---@param needle string
function StringUtil.strip_suffix(s, needle)
  if not StringUtil.ends_with(s, needle) then
    return s
  end

  return s:sub(1, #s - #needle)
end

return StringUtil
