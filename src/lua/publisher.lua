--- Here goes everything that does not belong anywhere else. Other parts are font handling, the command
--- list, page and gridsetup, debugging and initialization. We start with the function publisher#dothings that
--- initializes some variables and starts processing (publisher#dispatch())
--
--  publisher.lua
--  speedata publisher
--
--  For a list of authors see `git blame'
--  See file COPYING in the root directory for license info.

file_start("publisher.lua")

barcodes = do_luafile("barcodes.lua")
local luxor = do_luafile("luxor.lua")

local http = require("socket.http")
local url = require("socket_url")
local spotcolors = require("spotcolors")

xpath = do_luafile("xpath.lua")

local commands     = require("publisher.commands")
local page         = require("publisher.page")
local translations = require("translations")
local fontloader   = require("fonts.fontloader")
local paragraph    = require("paragraph")
local fonts        = require("publisher.fonts")

local env_publisherversion = os.getenv("PUBLISHERVERSION")

module(...,package.seeall)


do_luafile("layout_functions.lua")


--- One big point (DTP point, PostScript point) is approx. 65781 scaled points.
factor = 65781

--- Attributes
--- ----------
--- Attributes are attached to nodes, so we can store information that are not present in the
--- nodes themselves or are evaluated later on (such as font selection - when generating glyph
--- nodes, we don't yet know what font the user will use).
---
--- Attributes may have any number, they just need to be constant across the whole source.
att_fontfamily     = 1
att_italic         = 2
att_bold           = 3
att_script         = 4
att_underline      = 5
att_indent         = 6 -- see textformats for details
att_rows           = 7 -- see textformats for details

att_origin         = 98 -- for debugging purpose
att_debug          = 99 -- for debugging purposes

--- These attributes are for image shifting. The amount of shift up/left can
--- be negative and is counted in scaled points.
att_shift_left     = 100
att_shift_up       = 101

--- A tie glue (U+00A0) is a non-breaking space
att_tie_glue       = 201

--- These attributes are used in tabular material
att_space_prio     = 300
att_space_amount   = 301

att_break_below_forbidden = 400
att_break_above           = 401
att_omit_at_top           = 402
att_use_as_head           = 403
-- HTML tables should not be paragraph:format()ted
att_dont_format           = 404

--- `att_is_table_row` is used in `tabular.lua` and if set to 1, it denotes
--- a regular table row, and not a spacer. Spacers must not appear
--- at the top or the bottom of a table, unless forced to.
att_is_table_row    = 500
att_tr_dynamic_data = 501

-- for border-collapse (vertical)
att_tr_shift_up     = 550

-- Force a hbox line height
att_lineheight = 600

-- server-mode / linebreaking
att_keep = 700

-- attributes for glue
att_lederwd = 800

-- Debugging / see att_origin
origin_table = 1
origin_vspace = 2
origin_align_top = 3
origin_image = 4

origin_finishpar = 6
origin_text = 7
origin_setcolor = 8
origin_setcolorifnecessary = 9
origin_paragraph = 10

user_defined_addtolist = 1
user_defined_bookmark  = 2
user_defined_mark      = 3
user_defined_marker    = 4
user_defined_mark_append = 5


glue_spec_node = node.id("glue_spec")
glue_node      = node.id("glue")
glyph_node     = node.id("glyph")
disc_node      = node.id("disc")
rule_node      = node.id("rule")
penalty_node   = node.id("penalty")
whatsit_node   = node.id("whatsit")
hlist_node     = node.id("hlist")
vlist_node     = node.id("vlist")

local t = node.whatsits()
for k,v in pairs(node.whatsits()) do
    if v == "user_defined" then
        -- for action/mark command
        user_defined_whatsit = k
    end
end

-- sd:alternating
alternating = {}
alternating_value = {}


default_areaname = "_default_area"

-- The name of the next requested page
nextpage = nil

-- the language of the layout instructions ('en' or 'de')
current_layoutlanguage = nil

-- The document language
defaultlanguage = 0

-- Startpage
current_pagenumber = 1

pages = {}

-- CSS properties. Use `:matches(tbl)` to find a matching rule. `tbl` has the following structure: `{element=..., id=..., class=... }`
css = do_luafile("css.lua"):new()

-- The defaults (set in the layout instructions file)
options = {
    imagenotfounderror = true,
    gridwidth   = tex.sp("10mm"),
    gridheight  = tex.sp("10mm"),
    gridcells_x = 0,
    gridcells_y = 0,
}

-- List of virtual areas. Key is the group name and value is
-- a hash with keys contents (a nodelist) and grid (grid).
groups    = {}

-- sometimes we want to save pages for later reuse. Keys are pagestore names
pagestore = {}

-- to be used for translations
translated_values = nil


viewerpreferences = {}

-- The spot colors used in the document (even when discarded)
used_spotcolors = {}

-- The predefined colors. index = 1 because we "know" that black will be the first registered color.
colors  = {
  black = { model="gray", g = "0", pdfstring = " 0 G 0 g ", index = 1 },
  aliceblue = { model="rgb", r="0.941" , g="0.973" , b="1" , pdfstring = "0.941 0.973 1 rg 0.941 0.973 1 RG", index = 2},
  orange = { model="rgb", r="1" , g="0.647" , b="0" , pdfstring = "1 0.647 0 rg 1 0.647 0 RG", index = 3},
  rebeccapurple = { model="rgb", r="0.4" , g="0.2" , b="0.6" , pdfstring = "0.4 0.2 0.6 rg 0.4 0.2 0.6 RG", index = 4},
  antiquewhite = { model="rgb", r="0.98" , g="0.922" , b="0.843" , pdfstring = "0.98 0.922 0.843 rg 0.98 0.922 0.843 RG", index = 5},
  aqua = { model="rgb", r="0" , g="1" , b="1" , pdfstring = "0 1 1 rg 0 1 1 RG", index = 6},
  aquamarine = { model="rgb", r="0.498" , g="1" , b="0.831" , pdfstring = "0.498 1 0.831 rg 0.498 1 0.831 RG", index = 7},
  azure = { model="rgb", r="0.941" , g="1" , b="1" , pdfstring = "0.941 1 1 rg 0.941 1 1 RG", index = 8},
  beige = { model="rgb", r="0.961" , g="0.961" , b="0.863" , pdfstring = "0.961 0.961 0.863 rg 0.961 0.961 0.863 RG", index = 9},
  bisque = { model="rgb", r="1" , g="0.894" , b="0.769" , pdfstring = "1 0.894 0.769 rg 1 0.894 0.769 RG", index = 10},
  blanchedalmond = { model="rgb", r="1" , g="0.894" , b="0.769" , pdfstring = "1 0.894 0.769 rg 1 0.894 0.769 RG", index = 11},
  blue = { model="rgb", r="0" , g="0" , b="1" , pdfstring = "0 0 1 rg 0 0 1 RG", index = 12},
  blueviolet = { model="rgb", r="0.541" , g="0.169" , b="0.886" , pdfstring = "0.541 0.169 0.886 rg 0.541 0.169 0.886 RG", index = 13},
  brown = { model="rgb", r="0.647" , g="0.165" , b="0.165" , pdfstring = "0.647 0.165 0.165 rg 0.647 0.165 0.165 RG", index = 14},
  burlywood = { model="rgb", r="0.871" , g="0.722" , b="0.529" , pdfstring = "0.871 0.722 0.529 rg 0.871 0.722 0.529 RG", index = 15},
  cadetblue = { model="rgb", r="0.373" , g="0.62" , b="0.627" , pdfstring = "0.373 0.62 0.627 rg 0.373 0.62 0.627 RG", index = 16},
  chartreuse = { model="rgb", r="0.498" , g="1" , b="0" , pdfstring = "0.498 1 0 rg 0.498 1 0 RG", index = 17},
  chocolate = { model="rgb", r="0.824" , g="0.412" , b="0.118" , pdfstring = "0.824 0.412 0.118 rg 0.824 0.412 0.118 RG", index = 18},
  coral = { model="rgb", r="1" , g="0.498" , b="0.314" , pdfstring = "1 0.498 0.314 rg 1 0.498 0.314 RG", index = 19},
  cornflowerblue = { model="rgb", r="0.392" , g="0.584" , b="0.929" , pdfstring = "0.392 0.584 0.929 rg 0.392 0.584 0.929 RG", index = 20},
  cornsilk = { model="rgb", r="1" , g="0.973" , b="0.863" , pdfstring = "1 0.973 0.863 rg 1 0.973 0.863 RG", index = 21},
  crimson = { model="rgb", r="0.863" , g="0.078" , b="0.235" , pdfstring = "0.863 0.078 0.235 rg 0.863 0.078 0.235 RG", index = 22},
  darkblue = { model="rgb", r="0" , g="0" , b="0.545" , pdfstring = "0 0 0.545 rg 0 0 0.545 RG", index = 23},
  darkcyan = { model="rgb", r="0" , g="0.545" , b="0.545" , pdfstring = "0 0.545 0.545 rg 0 0.545 0.545 RG", index = 24},
  darkgoldenrod = { model="rgb", r="0.722" , g="0.525" , b="0.043" , pdfstring = "0.722 0.525 0.043 rg 0.722 0.525 0.043 RG", index = 25},
  darkgray = { model="rgb", r="0.663" , g="0.663" , b="0.663" , pdfstring = "0.663 0.663 0.663 rg 0.663 0.663 0.663 RG", index = 26},
  darkgreen = { model="rgb", r="0" , g="0.392" , b="0" , pdfstring = "0 0.392 0 rg 0 0.392 0 RG", index = 27},
  darkgrey = { model="rgb", r="0.663" , g="0.663" , b="0.663" , pdfstring = "0.663 0.663 0.663 rg 0.663 0.663 0.663 RG", index = 28},
  darkkhaki = { model="rgb", r="0.741" , g="0.718" , b="0.42" , pdfstring = "0.741 0.718 0.42 rg 0.741 0.718 0.42 RG", index = 29},
  darkmagenta = { model="rgb", r="0.545" , g="0" , b="0.545" , pdfstring = "0.545 0 0.545 rg 0.545 0 0.545 RG", index = 30},
  darkolivegreen = { model="rgb", r="0.333" , g="0.42" , b="0.184" , pdfstring = "0.333 0.42 0.184 rg 0.333 0.42 0.184 RG", index = 31},
  darkorange = { model="rgb", r="1" , g="0.549" , b="0" , pdfstring = "1 0.549 0 rg 1 0.549 0 RG", index = 32},
  darkorchid = { model="rgb", r="0.6" , g="0.196" , b="0.8" , pdfstring = "0.6 0.196 0.8 rg 0.6 0.196 0.8 RG", index = 33},
  darkred = { model="rgb", r="0.545" , g="0" , b="0" , pdfstring = "0.545 0 0 rg 0.545 0 0 RG", index = 34},
  darksalmon = { model="rgb", r="0.914" , g="0.588" , b="0.478" , pdfstring = "0.914 0.588 0.478 rg 0.914 0.588 0.478 RG", index = 35},
  darkseagreen = { model="rgb", r="0.561" , g="0.737" , b="0.561" , pdfstring = "0.561 0.737 0.561 rg 0.561 0.737 0.561 RG", index = 36},
  darkslateblue = { model="rgb", r="0.282" , g="0.239" , b="0.545" , pdfstring = "0.282 0.239 0.545 rg 0.282 0.239 0.545 RG", index = 37},
  darkslategray = { model="rgb", r="0.184" , g="0.31" , b="0.31" , pdfstring = "0.184 0.31 0.31 rg 0.184 0.31 0.31 RG", index = 38},
  darkslategrey = { model="rgb", r="0.184" , g="0.31" , b="0.31" , pdfstring = "0.184 0.31 0.31 rg 0.184 0.31 0.31 RG", index = 39},
  darkturquoise = { model="rgb", r="0" , g="0.808" , b="0.82" , pdfstring = "0 0.808 0.82 rg 0 0.808 0.82 RG", index = 40},
  darkviolet = { model="rgb", r="0.58" , g="0" , b="0.827" , pdfstring = "0.58 0 0.827 rg 0.58 0 0.827 RG", index = 41},
  deeppink = { model="rgb", r="1" , g="0.078" , b="0.576" , pdfstring = "1 0.078 0.576 rg 1 0.078 0.576 RG", index = 42},
  deepskyblue = { model="rgb", r="0" , g="0.749" , b="1" , pdfstring = "0 0.749 1 rg 0 0.749 1 RG", index = 43},
  dimgray = { model="rgb", r="0.412" , g="0.412" , b="0.412" , pdfstring = "0.412 0.412 0.412 rg 0.412 0.412 0.412 RG", index = 44},
  dimgrey = { model="rgb", r="0.412" , g="0.412" , b="0.412" , pdfstring = "0.412 0.412 0.412 rg 0.412 0.412 0.412 RG", index = 45},
  dodgerblue = { model="rgb", r="0.118" , g="0.565" , b="1" , pdfstring = "0.118 0.565 1 rg 0.118 0.565 1 RG", index = 46},
  firebrick = { model="rgb", r="0.698" , g="0.133" , b="0.133" , pdfstring = "0.698 0.133 0.133 rg 0.698 0.133 0.133 RG", index = 47},
  floralwhite = { model="rgb", r="1" , g="0.98" , b="0.941" , pdfstring = "1 0.98 0.941 rg 1 0.98 0.941 RG", index = 48},
  forestgreen = { model="rgb", r="0.133" , g="0.545" , b="0.133" , pdfstring = "0.133 0.545 0.133 rg 0.133 0.545 0.133 RG", index = 49},
  fuchsia = { model="rgb", r="1" , g="0" , b="1" , pdfstring = "1 0 1 rg 1 0 1 RG", index = 50},
  gainsboro = { model="rgb", r="0.863" , g="0.863" , b="0.863" , pdfstring = "0.863 0.863 0.863 rg 0.863 0.863 0.863 RG", index = 51},
  ghostwhite = { model="rgb", r="0.973" , g="0.973" , b="1" , pdfstring = "0.973 0.973 1 rg 0.973 0.973 1 RG", index = 52},
  gold = { model="rgb", r="1" , g="0.843" , b="0" , pdfstring = "1 0.843 0 rg 1 0.843 0 RG", index = 53},
  goldenrod = { model="rgb", r="0.855" , g="0.647" , b="0.125" , pdfstring = "0.855 0.647 0.125 rg 0.855 0.647 0.125 RG", index = 54},
  gray = { model="rgb", r="0.502" , g="0.502" , b="0.502" , pdfstring = "0.502 0.502 0.502 rg 0.502 0.502 0.502 RG", index = 55},
  green = { model="rgb", r="0" , g="0.502" , b="0" , pdfstring = "0 0.502 0 rg 0 0.502 0 RG", index = 56},
  greenyellow = { model="rgb", r="0.678" , g="1" , b="0.184" , pdfstring = "0.678 1 0.184 rg 0.678 1 0.184 RG", index = 57},
  grey = { model="rgb", r="0.502" , g="0.502" , b="0.502" , pdfstring = "0.502 0.502 0.502 rg 0.502 0.502 0.502 RG", index = 58},
  honeydew = { model="rgb", r="0.941" , g="1" , b="0.941" , pdfstring = "0.941 1 0.941 rg 0.941 1 0.941 RG", index = 59},
  hotpink = { model="rgb", r="1" , g="0.412" , b="0.706" , pdfstring = "1 0.412 0.706 rg 1 0.412 0.706 RG", index = 60},
  indianred = { model="rgb", r="0.804" , g="0.361" , b="0.361" , pdfstring = "0.804 0.361 0.361 rg 0.804 0.361 0.361 RG", index = 61},
  indigo = { model="rgb", r="0.294" , g="0" , b="0.51" , pdfstring = "0.294 0 0.51 rg 0.294 0 0.51 RG", index = 62},
  ivory = { model="rgb", r="1" , g="1" , b="0.941" , pdfstring = "1 1 0.941 rg 1 1 0.941 RG", index = 63},
  khaki = { model="rgb", r="0.941" , g="0.902" , b="0.549" , pdfstring = "0.941 0.902 0.549 rg 0.941 0.902 0.549 RG", index = 64},
  lavender = { model="rgb", r="0.902" , g="0.902" , b="0.98" , pdfstring = "0.902 0.902 0.98 rg 0.902 0.902 0.98 RG", index = 65},
  lavenderblush = { model="rgb", r="1" , g="0.941" , b="0.961" , pdfstring = "1 0.941 0.961 rg 1 0.941 0.961 RG", index = 66},
  lawngreen = { model="rgb", r="0.486" , g="0.988" , b="0" , pdfstring = "0.486 0.988 0 rg 0.486 0.988 0 RG", index = 67},
  lemonchiffon = { model="rgb", r="1" , g="0.98" , b="0.804" , pdfstring = "1 0.98 0.804 rg 1 0.98 0.804 RG", index = 68},
  lightblue = { model="rgb", r="0.678" , g="0.847" , b="0.902" , pdfstring = "0.678 0.847 0.902 rg 0.678 0.847 0.902 RG", index = 69},
  lightcoral = { model="rgb", r="0.941" , g="0.502" , b="0.502" , pdfstring = "0.941 0.502 0.502 rg 0.941 0.502 0.502 RG", index = 70},
  lightcyan = { model="rgb", r="0.878" , g="1" , b="1" , pdfstring = "0.878 1 1 rg 0.878 1 1 RG", index = 71},
  lightgoldenrodyellow = { model="rgb", r="0.98" , g="0.98" , b="0.824" , pdfstring = "0.98 0.98 0.824 rg 0.98 0.98 0.824 RG", index = 72},
  lightgray = { model="rgb", r="0.827" , g="0.827" , b="0.827" , pdfstring = "0.827 0.827 0.827 rg 0.827 0.827 0.827 RG", index = 73},
  lightgreen = { model="rgb", r="0.565" , g="0.933" , b="0.565" , pdfstring = "0.565 0.933 0.565 rg 0.565 0.933 0.565 RG", index = 74},
  lightgrey = { model="rgb", r="0.827" , g="0.827" , b="0.827" , pdfstring = "0.827 0.827 0.827 rg 0.827 0.827 0.827 RG", index = 75},
  lightpink = { model="rgb", r="1" , g="0.714" , b="0.757" , pdfstring = "1 0.714 0.757 rg 1 0.714 0.757 RG", index = 76},
  lightsalmon = { model="rgb", r="1" , g="0.627" , b="0.478" , pdfstring = "1 0.627 0.478 rg 1 0.627 0.478 RG", index = 77},
  lightseagreen = { model="rgb", r="0.125" , g="0.698" , b="0.667" , pdfstring = "0.125 0.698 0.667 rg 0.125 0.698 0.667 RG", index = 78},
  lightskyblue = { model="rgb", r="0.529" , g="0.808" , b="0.98" , pdfstring = "0.529 0.808 0.98 rg 0.529 0.808 0.98 RG", index = 79},
  lightslategray = { model="rgb", r="0.467" , g="0.533" , b="0.6" , pdfstring = "0.467 0.533 0.6 rg 0.467 0.533 0.6 RG", index = 80},
  lightslategrey = { model="rgb", r="0.467" , g="0.533" , b="0.6" , pdfstring = "0.467 0.533 0.6 rg 0.467 0.533 0.6 RG", index = 81},
  lightsteelblue = { model="rgb", r="0.69" , g="0.769" , b="0.871" , pdfstring = "0.69 0.769 0.871 rg 0.69 0.769 0.871 RG", index = 82},
  lightyellow = { model="rgb", r="1" , g="1" , b="0.878" , pdfstring = "1 1 0.878 rg 1 1 0.878 RG", index = 83},
  lime = { model="rgb", r="0" , g="1" , b="0" , pdfstring = "0 1 0 rg 0 1 0 RG", index = 84},
  limegreen = { model="rgb", r="0.196" , g="0.804" , b="0.196" , pdfstring = "0.196 0.804 0.196 rg 0.196 0.804 0.196 RG", index = 85},
  linen = { model="rgb", r="0.98" , g="0.941" , b="0.902" , pdfstring = "0.98 0.941 0.902 rg 0.98 0.941 0.902 RG", index = 86},
  maroon = { model="rgb", r="0.502" , g="0" , b="0" , pdfstring = "0.502 0 0 rg 0.502 0 0 RG", index = 87},
  mediumaquamarine = { model="rgb", r="0.4" , g="0.804" , b="0.667" , pdfstring = "0.4 0.804 0.667 rg 0.4 0.804 0.667 RG", index = 88},
  mediumblue = { model="rgb", r="0" , g="0" , b="0.804" , pdfstring = "0 0 0.804 rg 0 0 0.804 RG", index = 89},
  mediumorchid = { model="rgb", r="0.729" , g="0.333" , b="0.827" , pdfstring = "0.729 0.333 0.827 rg 0.729 0.333 0.827 RG", index = 90},
  mediumpurple = { model="rgb", r="0.576" , g="0.439" , b="0.859" , pdfstring = "0.576 0.439 0.859 rg 0.576 0.439 0.859 RG", index = 91},
  mediumseagreen = { model="rgb", r="0.235" , g="0.702" , b="0.443" , pdfstring = "0.235 0.702 0.443 rg 0.235 0.702 0.443 RG", index = 92},
  mediumslateblue = { model="rgb", r="0.482" , g="0.408" , b="0.933" , pdfstring = "0.482 0.408 0.933 rg 0.482 0.408 0.933 RG", index = 93},
  mediumspringgreen = { model="rgb", r="0" , g="0.98" , b="0.604" , pdfstring = "0 0.98 0.604 rg 0 0.98 0.604 RG", index = 94},
  mediumturquoise = { model="rgb", r="0.282" , g="0.82" , b="0.8" , pdfstring = "0.282 0.82 0.8 rg 0.282 0.82 0.8 RG", index = 95},
  mediumvioletred = { model="rgb", r="0.78" , g="0.082" , b="0.522" , pdfstring = "0.78 0.082 0.522 rg 0.78 0.082 0.522 RG", index = 96},
  midnightblue = { model="rgb", r="0.098" , g="0.098" , b="0.439" , pdfstring = "0.098 0.098 0.439 rg 0.098 0.098 0.439 RG", index = 97},
  mintcream = { model="rgb", r="0.961" , g="1" , b="0.98" , pdfstring = "0.961 1 0.98 rg 0.961 1 0.98 RG", index = 98},
  mistyrose = { model="rgb", r="1" , g="0.894" , b="0.882" , pdfstring = "1 0.894 0.882 rg 1 0.894 0.882 RG", index = 99},
  moccasin = { model="rgb", r="1" , g="0.894" , b="0.71" , pdfstring = "1 0.894 0.71 rg 1 0.894 0.71 RG", index = 100},
  navajowhite = { model="rgb", r="1" , g="0.871" , b="0.678" , pdfstring = "1 0.871 0.678 rg 1 0.871 0.678 RG", index = 101},
  navy = { model="rgb", r="0" , g="0" , b="0.502" , pdfstring = "0 0 0.502 rg 0 0 0.502 RG", index = 102},
  oldlace = { model="rgb", r="0.992" , g="0.961" , b="0.902" , pdfstring = "0.992 0.961 0.902 rg 0.992 0.961 0.902 RG", index = 103},
  olive = { model="rgb", r="0.502" , g="0.502" , b="0" , pdfstring = "0.502 0.502 0 rg 0.502 0.502 0 RG", index = 104},
  olivedrab = { model="rgb", r="0.42" , g="0.557" , b="0.137" , pdfstring = "0.42 0.557 0.137 rg 0.42 0.557 0.137 RG", index = 105},
  orangered = { model="rgb", r="1" , g="0.271" , b="0" , pdfstring = "1 0.271 0 rg 1 0.271 0 RG", index = 106},
  orchid = { model="rgb", r="0.855" , g="0.439" , b="0.839" , pdfstring = "0.855 0.439 0.839 rg 0.855 0.439 0.839 RG", index = 107},
  palegoldenrod = { model="rgb", r="0.933" , g="0.91" , b="0.667" , pdfstring = "0.933 0.91 0.667 rg 0.933 0.91 0.667 RG", index = 108},
  palegreen = { model="rgb", r="0.596" , g="0.984" , b="0.596" , pdfstring = "0.596 0.984 0.596 rg 0.596 0.984 0.596 RG", index = 109},
  paleturquoise = { model="rgb", r="0.686" , g="0.933" , b="0.933" , pdfstring = "0.686 0.933 0.933 rg 0.686 0.933 0.933 RG", index = 110},
  palevioletred = { model="rgb", r="0.859" , g="0.439" , b="0.576" , pdfstring = "0.859 0.439 0.576 rg 0.859 0.439 0.576 RG", index = 111},
  papayawhip = { model="rgb", r="1" , g="0.937" , b="0.835" , pdfstring = "1 0.937 0.835 rg 1 0.937 0.835 RG", index = 112},
  peachpuff = { model="rgb", r="1" , g="0.855" , b="0.725" , pdfstring = "1 0.855 0.725 rg 1 0.855 0.725 RG", index = 113},
  peru = { model="rgb", r="0.804" , g="0.522" , b="0.247" , pdfstring = "0.804 0.522 0.247 rg 0.804 0.522 0.247 RG", index = 114},
  pink = { model="rgb", r="1" , g="0.753" , b="0.796" , pdfstring = "1 0.753 0.796 rg 1 0.753 0.796 RG", index = 115},
  plum = { model="rgb", r="0.867" , g="0.627" , b="0.867" , pdfstring = "0.867 0.627 0.867 rg 0.867 0.627 0.867 RG", index = 116},
  powderblue = { model="rgb", r="0.69" , g="0.878" , b="0.902" , pdfstring = "0.69 0.878 0.902 rg 0.69 0.878 0.902 RG", index = 117},
  purple = { model="rgb", r="0.502" , g="0" , b="0.502" , pdfstring = "0.502 0 0.502 rg 0.502 0 0.502 RG", index = 118},
  red = { model="rgb", r="1" , g="0" , b="0" , pdfstring = "1 0 0 rg 1 0 0 RG", index = 119},
  rosybrown = { model="rgb", r="0.737" , g="0.561" , b="0.561" , pdfstring = "0.737 0.561 0.561 rg 0.737 0.561 0.561 RG", index = 120},
  royalblue = { model="rgb", r="0.255" , g="0.412" , b="0.882" , pdfstring = "0.255 0.412 0.882 rg 0.255 0.412 0.882 RG", index = 121},
  saddlebrown = { model="rgb", r="0.545" , g="0.271" , b="0.075" , pdfstring = "0.545 0.271 0.075 rg 0.545 0.271 0.075 RG", index = 122},
  salmon = { model="rgb", r="0.98" , g="0.502" , b="0.447" , pdfstring = "0.98 0.502 0.447 rg 0.98 0.502 0.447 RG", index = 123},
  sandybrown = { model="rgb", r="0.957" , g="0.643" , b="0.376" , pdfstring = "0.957 0.643 0.376 rg 0.957 0.643 0.376 RG", index = 124},
  seagreen = { model="rgb", r="0.18" , g="0.545" , b="0.341" , pdfstring = "0.18 0.545 0.341 rg 0.18 0.545 0.341 RG", index = 125},
  seashell = { model="rgb", r="1" , g="0.961" , b="0.933" , pdfstring = "1 0.961 0.933 rg 1 0.961 0.933 RG", index = 126},
  sienna = { model="rgb", r="0.627" , g="0.322" , b="0.176" , pdfstring = "0.627 0.322 0.176 rg 0.627 0.322 0.176 RG", index = 127},
  silver = { model="rgb", r="0.753" , g="0.753" , b="0.753" , pdfstring = "0.753 0.753 0.753 rg 0.753 0.753 0.753 RG", index = 128},
  skyblue = { model="rgb", r="0.529" , g="0.808" , b="0.922" , pdfstring = "0.529 0.808 0.922 rg 0.529 0.808 0.922 RG", index = 129},
  slateblue = { model="rgb", r="0.416" , g="0.353" , b="0.804" , pdfstring = "0.416 0.353 0.804 rg 0.416 0.353 0.804 RG", index = 130},
  slategray = { model="rgb", r="0.439" , g="0.502" , b="0.565" , pdfstring = "0.439 0.502 0.565 rg 0.439 0.502 0.565 RG", index = 131},
  slategrey = { model="rgb", r="0.439" , g="0.502" , b="0.565" , pdfstring = "0.439 0.502 0.565 rg 0.439 0.502 0.565 RG", index = 132},
  snow = { model="rgb", r="1" , g="0.98" , b="0.98" , pdfstring = "1 0.98 0.98 rg 1 0.98 0.98 RG", index = 133},
  springgreen = { model="rgb", r="0" , g="1" , b="0.498" , pdfstring = "0 1 0.498 rg 0 1 0.498 RG", index = 134},
  steelblue = { model="rgb", r="0.275" , g="0.51" , b="0.706" , pdfstring = "0.275 0.51 0.706 rg 0.275 0.51 0.706 RG", index = 135},
  tan = { model="rgb", r="0.824" , g="0.706" , b="0.549" , pdfstring = "0.824 0.706 0.549 rg 0.824 0.706 0.549 RG", index = 136},
  teal = { model="rgb", r="0" , g="0.502" , b="0.502" , pdfstring = "0 0.502 0.502 rg 0 0.502 0.502 RG", index = 137},
  thistle = { model="rgb", r="0.847" , g="0.749" , b="0.847" , pdfstring = "0.847 0.749 0.847 rg 0.847 0.749 0.847 RG", index = 138},
  tomato = { model="rgb", r="1" , g="0.388" , b="0.278" , pdfstring = "1 0.388 0.278 rg 1 0.388 0.278 RG", index = 139},
  turquoise = { model="rgb", r="0.251" , g="0.878" , b="0.816" , pdfstring = "0.251 0.878 0.816 rg 0.251 0.878 0.816 RG", index = 140},
  violet = { model="rgb", r="0.933" , g="0.51" , b="0.933" , pdfstring = "0.933 0.51 0.933 rg 0.933 0.51 0.933 RG", index = 141},
  wheat = { model="rgb", r="0.961" , g="0.871" , b="0.702" , pdfstring = "0.961 0.871 0.702 rg 0.961 0.871 0.702 RG", index = 142},
  white = { model="gray", g="1" , pdfstring = "1 G 1 g", index = 143},
  whitesmoke = { model="rgb", r="0.961" , g="0.961" , b="0.961" , pdfstring = "0.961 0.961 0.961 rg 0.961 0.961 0.961 RG", index = 144},
  yellow = { model="rgb", r="1" , g="1" , b="0" , pdfstring = "1 1 0 rg 1 1 0 RG", index = 145},
  yellowgreen = { model="rgb", r="0.604" , g="0.804" , b="0.196" , pdfstring = "0.604 0.804 0.196 rg 0.604 0.804 0.196 RG", index = 146}
}

-- An array of defined colors
colortable = {"black","aliceblue", "orange", "rebeccapurple", "antiquewhite", "aqua", "aquamarine", "azure", "beige", "bisque", "blanchedalmond", "blue", "blueviolet", "brown", "burlywood", "cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue", "cornsilk", "crimson", "darkblue", "darkcyan", "darkgoldenrod", "darkgray", "darkgreen", "darkgrey", "darkkhaki", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen", "darkslateblue", "darkslategray", "darkslategrey", "darkturquoise", "darkviolet", "deeppink", "deepskyblue", "dimgray", "dimgrey", "dodgerblue", "firebrick", "floralwhite", "forestgreen", "fuchsia", "gainsboro", "ghostwhite", "gold", "goldenrod", "gray", "green", "greenyellow", "grey", "honeydew", "hotpink", "indianred", "indigo", "ivory", "khaki", "lavender", "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral", "lightcyan", "lightgoldenrodyellow", "lightgray", "lightgreen", "lightgrey", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray", "lightslategrey", "lightsteelblue", "lightyellow", "lime", "limegreen", "linen", "maroon", "mediumaquamarine", "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise", "mediumvioletred", "midnightblue", "mintcream", "mistyrose", "moccasin", "navajowhite", "navy", "oldlace", "olive", "olivedrab", "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise", "palevioletred", "papayawhip", "peachpuff", "peru", "pink", "plum", "powderblue", "purple", "red", "rosybrown", "royalblue", "saddlebrown", "salmon", "sandybrown", "seagreen", "seashell", "sienna", "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow", "springgreen", "steelblue", "tan", "teal", "thistle", "tomato", "turquoise", "violet", "wheat", "white", "whitesmoke", "yellow", "yellowgreen"}

setmetatable(colors,{  __index = function (tbl,key)
    if string.sub(key,1,1) ~= "#" then
        return nil
    end
    log("Defining color %q",key)
    local color = {}
    color.r, color.g, color.b = getrgb(key)
    color.pdfstring = string.format("%g %g %g rg %g %g %g RG", color.r, color.g, color.b, color.r,color.g, color.b)
    color.overprint = false
    color.model = model
    colortable[#colortable + 1] = key
    color.index = #colortable
    rawset(tbl,key,color)
    return color
end
 })

data_dispatcher = {}
user_defined_functions = { last = 0}
markers = {}

-- We will have to remember the current group and grid
current_group = nil
current_grid = nil

-- paragaph, table and textblock should set them
current_fontfamily = 0

-- Used when bookmarks are inserted in a non-text context
intextblockcontext = 0

-- The array 'masterpages' has tables similar to these:
-- { is_pagetype = test, res = tab, name = pagetypename }
-- where `is_pagetype` is an xpath expression to be evaluated,
-- `res` is a table with layoutxml instructions
-- `name` is a string.
masterpages = {}


-- if true, look for lowercase files
lowercase = false

--- Text formats is a hash with arbitrary names as keys and the values
--- are tables with alignment and indent. indent is the amount of
--- indentation in sp. alignment is one of "leftaligned", "rightaligned",
--- "centered" and "justified"
textformats = {
    text           = { indent = 0, alignment="justified",   rows = 1, orphan = false, widow = false},
    __centered     = { indent = 0, alignment="centered",    rows = 1},
    __leftaligned  = { indent = 0, alignment="leftaligned", rows = 1},
    __rightaligned = { indent = 0, alignment="rightaligned",rows = 1},
    __justified    = { indent = 0, alignment="justified",   rows = 1},
    centered       = { indent = 0, alignment="centered",    rows = 1},
    left           = { indent = 0, alignment="leftaligned", rows = 1},
    right          = { indent = 0, alignment="rightaligned",rows = 1},
    zentriert      = { indent = 0, alignment="centered",    rows = 1},
    links          = { indent = 0, alignment="leftaligned", rows = 1},
    rechts         = { indent = 0, alignment="rightaligned",rows = 1},
}


--- The bookmarks table has the format
---
---     bookmarks = {
---       { --- first bookmark
---         name = "outline 1" destination = "..." open = true,
---          { name = "outline 1.1", destination = "..." },
---          { name = "outline 1.2", destination = "..." }
---       },
---       { -- second bookmark
---         name = "outline 2" destination = "..." open = false,
---          { name = "outline 2.1", destination = "..." },
---          { name = "outline 2.2", destination = "..." }
---
---       }
---     }
bookmarks = {}

--- A table with key namespace prefix (`de` or `en`) and value namespace. Example:
---
---     {
---       [""] = "urn:speedata.de:2009/publisher/de"
---       sd = "urn:speedata:2009/publisher/functions/de"
---     }
namespaces_layout = nil

--- We need the separator for writing files in a directory structure (image cace for now)
os_separator = "/"
if os.type == "windows" then
    os_separator = "\\"
end

-- A very large length
maxdimen = 1073741823

-- It's convenient to just copy the stretching glue instead of writing
-- the stretch etc. over and over again.
glue_stretch2 = node.new("glue")
glue_stretch2.spec = node.new("glue_spec")
glue_stretch2.spec.stretch = 2^16
glue_stretch2.spec.stretch_order = 2

messages = {}

--- The dispatch table maps every element in the layout xml to a command in the `commands.lua` file.
local dispatch_table = {
    A                       = commands.a,
    Action                  = commands.action,
    AddToList               = commands.add_to_list,
    AtPageCreation          = commands.atpagecreation,
    AtPageShipout           = commands.atpageshipout,
    Attribute               = commands.attribute,
    B                       = commands.bold,
    Barcode                 = commands.barcode,
    Bookmark                = commands.bookmark,
    Box                     = commands.box,
    Br                      = commands.br,
    Circle                  = commands.circle,
    Color                   = commands.color,
    Column                  = commands.column,
    Columns                 = commands.columns,
    ["Copy-of"]             = commands.copy_of,
    DefineColor             = commands.define_color,
    DefineFontfamily        = commands.define_fontfamily,
    DefineTextformat        = commands.define_textformat,
    Element                 = commands.element,
    EmptyLine               = commands.emptyline,
    Fontface                = commands.fontface,
    ForAll                  = commands.forall,
    Frame                  = commands.frame,
    Grid                    = commands.grid,
    Group                   = commands.group,
    HSpace                  = commands.hspace,
    Hyphenation             = commands.hyphenation,
    I                       = commands.italic,
    Image                   = commands.image,
    Include                 = commands.include,
    InsertPages             = commands.insert_pages,
    Li                      = commands.li,
    LoadDataset             = commands.load_dataset,
    LoadFontfile            = commands.load_fontfile,
    Loop                    = commands.loop,
    Makeindex               = commands.makeindex,
    Margin                  = commands.margin,
    Mark                    = commands.mark,
    Message                 = commands.message,
    NewPage                 = commands.new_page,
    NextFrame               = commands.next_frame,
    NextRow                 = commands.next_row,
    NoBreak                 = commands.nobreak,
    Ol                      = commands.ol,
    Options                 = commands.options,
    Output                  = commands.output,
    Overlay                 = commands.overlay,
    Pageformat              = commands.page_format,
    Pagetype                = commands.pagetype,
    Paragraph               = commands.paragraph,
    PDFOptions              = commands.pdfoptions,
    PlaceObject             = commands.place_object,
    Position                = commands.position,
    PositioningArea         = commands.positioning_area,
    PositioningFrame        = commands.positioning_frame,
    ProcessNode             = commands.process_node,
    ProcessRecord           = commands.process_node,
    Record                  = commands.record,
    Rule                    = commands.rule,
    SaveDataset             = commands.save_dataset,
    SavePages               = commands.save_pages,
    Sequence                = commands.sequence,
    SetGrid                 = commands.set_grid,
    SetVariable             = commands.setvariable,
    SortSequence            = commands.sort_sequence,
    Stylesheet              = commands.stylesheet,
    Sub                     = commands.sub,
    Sup                     = commands.sup,
    Switch                  = commands.switch,
    Table                   = commands.table,
    Tablefoot               = commands.tablefoot,
    Tablehead               = commands.tablehead,
    Tablerule               = commands.tablerule,
    Td                      = commands.td,
    Textblock               = commands.textblock,
    Text                    = commands.text,
    Tr                      = commands.tr,
    Transformation          = commands.transformation,
    U                       = commands.underline,
    Ul                      = commands.ul,
    Until                   = commands.until_do,
    URL                     = commands.url,
    Value                   = commands.value,
    Variable                = commands.variable,
    VSpace                  = commands.vspace,
    While                   = commands.while_do,
}


--- Return the value as an english string. The argument is in the
--- current language of the layout file (currently English and German).
--- All translations are only valid in a context which defaults to the
--- _global_ context.
function translate_value( value,context )
    -- If we don't have a values variable, it must be english
    if translated_values == nil then return value end
    context = context or "*"
    return translated_values[context][value] or value
end


--- The returned table is an array with hashes. The keys of these
--- hashes are `elementname` and `contents`. For example:
---
---     {
---       [1] = {
---         ["elementname"] = "Paragraph"
---         ["contents"] = {
---           ["nodelist"] = "<node    nil <  58515 >    nil : glyph 1>"
---         },
---       },
---     },
function dispatch(layoutxml,dataxml,options)
    local ret = {}
    local tmp
    if not layoutxml then
        err("No elements for dispatch, why?")
        return
    end
    for _,j in ipairs(layoutxml) do
        -- j a table, if it is an element in layoutxml
        if type(j)=="table" then
            local eltname = j[".__local_name"]
            if dispatch_table[eltname] ~= nil then
                tmp = dispatch_table[eltname](j,dataxml,options)

                -- Copy-of-elements can be resolveld immediately
                if eltname == "Copy-of" or eltname == "Switch" or eltname == "ForAll" or eltname == "Loop" or eltname == "Transformation" or eltname == "Frame" then
                    if type(tmp)=="table" then
                        for i=1,#tmp do
                            if tmp[i].contents then
                                ret[#ret + 1] = { elementname = tmp[i].elementname, contents = tmp[i].contents }
                            else
                                ret[#ret + 1] = { elementname = "elementstructure" , contents = { tmp[i] } }
                            end
                        end
                    end
                else
                    ret[#ret + 1] =   { elementname = eltname, contents = tmp }
                end
            else
                err("Unknown element found in layoutfile: %q", j[".__local_name"] or "???")
            end
        end
    end
    return ret
end

--- Convert the argument `str` (in UTF-8) to a string suitable for writing into the PDF file. The returned string starts with `<feff` and ends with `>`
function utf8_to_utf16_string_pdf( str )
    local ret = {}
    for s in string.utfvalues(str) do
        ret[#ret + 1] = fontloader.to_utf16(s)
    end
    local utf16str = "<feff" .. table.concat(ret) .. ">"
    return utf16str
end

--- Bookmarks are collected and later processed. This function (recursively)
--- creates TeX code from the generated tables.
function bookmarkstotex( tbl )
    local countstring
    local open_string
    if #tbl == 0 then
        countstring = ""
    else
        if tbl.open == "true" then
            open_string = ""
        else
            open_string = "-"
        end
        countstring = string.format("count %s%d",open_string,#tbl)
    end
    if tbl.destination then
        tex.sprint(string.format("\\pdfoutline goto num %s %s {%s}",tbl.destination, countstring ,utf8_to_utf16_string_pdf(tbl.name) ))
    end
    for i,v in ipairs(tbl) do
        bookmarkstotex(v)
    end
end

function page_initialized_p( pagenumber )
    return pages[pagenumber] ~= nil
end

-- Translate attributes and elements to english, so that
-- we don't need to translate them later again and again and again
function translate_layout(layoutxml,lang)
    local x
    for i=1,#layoutxml do
        x = layoutxml[i]
        if type(x) == "table" then
            local y = x[".__local_name"]
            local cmd = lang[y]
            if not cmd then
                if x[".__parent"][".__local_name"] ~= "Value" then
                    err("Unknown command %q in Layoutfile",y)
                end
            else
                x[".__local_name"] = cmd[1]
                x[".__name"] = cmd[1]
                for k,v in pairs(cmd) do
                    if type(k) == "string" then
                        if x[k] then
                            x[v] = x[k]
                        end
                    end
                end
                translate_layout(x,lang)
            end
        end
    end
end


--- Start the processing (`dothings()`)
--- -------------------------------
--- This is the entry point of the processing. It is called from publisher.spinit#main_loop.
function dothings()
    log("LuaTeX version %d.%d",tex.luatexversion,tex.luatexrevision)
    --- First we set some defaults.
    --- A4 paper is 210x297 mm
    set_pageformat(tex.sp("210mm"),tex.sp("297mm"))
    get_languagecode(os.getenv("SP_MAINLANGUAGE") or "en_GB")

    lowercase = os.getenv("SP_IGNORECASE") == "1"

    --- The free font family `TeXGyreHeros` is a Helvetica clone and is part of the
    --- [The TeX Gyre Collection of Fonts](http://www.gust.org.pl/projects/e-foundry/tex-gyre).
    --- We ship it in the distribution.
    fonts.load_fontfile("TeXGyreHeros-Regular",   "texgyreheros-regular.otf")
    fonts.load_fontfile("TeXGyreHeros-Bold",      "texgyreheros-bold.otf")
    fonts.load_fontfile("TeXGyreHeros-Italic",    "texgyreheros-italic.otf")
    fonts.load_fontfile("TeXGyreHeros-BoldItalic","texgyreheros-bolditalic.otf")
    --- Define a basic font family with name `text`:
    define_default_fontfamily()

    --- The server mode is quite interesting: we don't generate a PDF, but wait for requests and try to answer
    --- them. We rely on the internal communication (tcp) in publisher.server#servermode.
    if arg[2] == "___server___" then
        local s = require("publisher.server")
        s.servermode(tcp)
    else
        initialize_luatex_and_generate_pdf()
        -- The last thing is to put a stamp in the PDF
        pdf.immediateobj("(Created with the speedata Publisher - www.speedata.de)")
    end
end

-- When not in server mode, we initialize LuaTeX in such a way that
-- it has defaults, loads a layout file and a data file and
-- executes them both
function initialize_luatex_and_generate_pdf()

    --- The default page type has 1cm margin
    local onecm=tex.sp("1cm")
    masterpages[1] = { is_pagetype = "true()", res = { {elementname = "Margin", contents = function(_page) _page.grid:set_margin(onecm,onecm,onecm,onecm) end }}, name = "Default Page",ns={[""] = "urn:speedata.de:2009/publisher/en" } }
    xpath.set_variable("__maxwidth", tex.sp("190mm"))
    --- The `vars` file hold a lua document holding table
    local vars = loadfile(tex.jobname .. ".vars")()
    for k,v in pairs(vars) do
        xpath.set_variable(k,v)
    end


    --- Both the data and the layout instructions are written in XML.
    local layoutxml = load_xml(arg[2],"layout instructions")
    if not layoutxml then
        err("Without a valid layout-XML file, I can't really do anything.")
        exit()
    end

    --- Used in `xpath.lua` to find out which language the function is in.
    local ns = layoutxml[".__namespace"]
    if not ns then
        err("Cannot find the namespace of the layout file. What should I do?")
        exit()
    end

    --- The currently active layout language. One of `de` or `en`.
    current_layoutlanguage = string.gsub(ns,"urn:speedata.de:2009/publisher/","")
    if not (current_layoutlanguage=='de' or current_layoutlanguage=='en') then
        err("Cannot determine the language of the layout file.")
        exit()
    end

    if current_layoutlanguage ~= "en" then
        translated_values = translations[current_layoutlanguage]["__values"]
        translate_layout(layoutxml,translations[current_layoutlanguage])
    end

    if layoutxml.version then
        local version_mismatch = false
        local publisher_version = string.explode(env_publisherversion,".")
        local requested_version = string.explode(layoutxml.version,".")

        if publisher_version[1] ~= requested_version[1] then
            version_mismatch = true
        elseif publisher_version[2] < requested_version[2] then
            -- major number are same, minor are different
            version_mismatch = true
        elseif requested_version[3] and publisher_version[3] < requested_version[3] and publisher_version[2] == requested_version[2] then
            version_mismatch = true
        end
        if version_mismatch then
            err("Version mismatch. speedata Publisher is at version %s, requested version %s", env_publisherversion, layoutxml.version)
            exit()
        end
    end

    -- We define two graphic states for overprinting on and off.
    GS_State_OP_On  = pdf.immediateobj([[<< /Type/ExtGState /OP true /OPM 1 >>]])
    GS_State_OP_Off = pdf.immediateobj([[<< /Type/ExtGState /OP false >>]])
    tmp = os.getenv("SD_EXTRA_XML")
    if tmp and tmp ~= "" then
        for _,v in ipairs(string.explode(tmp,",")) do
            layoutxml[#layoutxml + 1] = luxor.parse_xml_file(v)
        end
    end

    dispatch(layoutxml)

    --- override options set in the `<Options>` element
    if arg[4] then
        for _,extopt in ipairs(string.explode(arg[4],",")) do
            if string.len(extopt) > 0 then
                local k,v = extopt:match("^(.+)=(.+)$")
                v = v:gsub("^\"(.*)\"$","%1")
                options[k]=v
            end
        end
    end
    if os.getenv("SP_VERBOSITY") == nil then
        options.verbosity = 0
    else
        options.verbosity = tonumber(os.getenv("SP_VERBOSITY"))
    end

    if options.showgrid == "false" then
        options.showgrid = false
    elseif options.showgrid == "true" then
        options.showgrid = true
    end

    if options.cutmarks == "true" then
        options.cutmarks = true
    elseif options.cutmarks == "false" then
        options.cutmarks = false
    end

    if options.trimmarks == "true" then
        options.trimmarks = true
    elseif options.trimmarks == "false" then
        options.trimmarks = false
    end

    if options.showgridallocation == "false" then
        options.showgridallocation = false
    elseif options.showgridallocation == "true" then
        options.showgridallocation = true
    end

    --- Set the starting page (which must be a number)
    if options.startpage then
        local num = options.startpage
        if num then
            current_pagenumber = num
            log("Set page number to %d",num)
        else
            err("Can't recognize starting page number %q",options.startpage)
        end
    end

    if options.colorprofile then
        spotcolors.set_colorprofile_filename(options.colorprofile)
    end

    local auxfilename = tex.jobname .. "-aux.xml"
    -- load help file if it exists
    if kpse.filelist[auxfilename] and options.resetmarks == false then
        local mark_tab = load_xml(auxfilename,"aux file",{ htmlentities = true, ignoreeol = true })
        for i=1,#mark_tab do
            local mt = mark_tab[i]
            if type(mt) == "table" and mt[".__local_name"] == "mark" then
                markers[mt.name] = { page = mt.page}
            end
        end
    end

    -- We allow the use of a dummy xml file for testing purpose
    local dataxml
    if arg[3] == "-dummy" then
        dataxml = luxor.parse_xml("<data />")
    elseif arg[3] == "-" then
        log("Reading from stdin")
        dataxml = luxor.parse_xml(io.stdin:read("*a"),{htmlentities = true})
    else
        dataxml = load_xml(arg[3],"data file",{ htmlentities = true, ignoreeol = ( options.ignoreeol or false ) })
    end
    if type(dataxml) ~= "table" then
        err("Something is wrong with the data: dataxml is not a table")
        exit()
    end

    --- Start data processing in the default mode (`""`)
    local tmp
    local name = dataxml[".__local_name"]
    xpath.set_variable("__position", 1)
    --- The rare case that the user has not any `Record` commands in the layout file:
    if not data_dispatcher[""] then
        err("Can't find »Record« command for the root node.")
        exit()
    end
    tmp = data_dispatcher[""][name]
    if tmp then
        dispatch(tmp,dataxml)
    end


    --- emit last page if necessary
    -- current_pagestore_name is set when in SavePages and nil otherwise
    if page_initialized_p(current_pagenumber) and current_pagestore_name == nil then
        dothingsbeforeoutput(pages[current_pagenumber])

        local n = node.vpack(pages[current_pagenumber].pagebox)

        tex.box[666] = n
        tex.shipout(666)
    end

    --- At this point, all pages are in the PDF
    local vp = {}
    if viewerpreferences.numcopies and viewerpreferences.numcopies > 1 and viewerpreferences.numcopies <= 5 then
        vp[#vp + 1] = string.format("/NumCopies %d", viewerpreferences.numcopies)
    end
    if viewerpreferences.printscaling and viewerpreferences.printscaling ~= ""  then
        vp[#vp + 1] = string.format("/PrintScaling /%s", viewerpreferences.printscaling)
    end
    if viewerpreferences.picktray ~= nil  then
        vp[#vp + 1] = string.format("/PickTrayByPDFSize %s", viewerpreferences.picktray)
    end

    if viewerpreferences.duplex ~= nil and viewerpreferences.duplex ~= "" then
        vp[#vp + 1] = string.format("/Duplex /%s", viewerpreferences.duplex)
    end

    local catalog = "/PageMode /UseOutlines"
    if #vp > 0 then
        catalog = catalog .. "/ViewerPreferences <<" .. table.concat(vp," ") .. ">>"
    end
    local creator = string.format("speedata Publisher %s, www.speedata.de",env_publisherversion)
    local info = string.format("/Creator (%s) ",creator)
    if pdf.setinfo then
        pdf.setcatalog(catalog)
        pdf.setinfo(info)
    else
        pdf.catalog = catalog
        pdf.info = info
    end

    --- Now put the bookmarks in the pdf
    for _,v in ipairs(bookmarks) do
        bookmarkstotex(v)
    end
    local tab = {}
    for k,v in pairs(markers) do
        tab[#tab + 1] = string.format("  <mark name=%q page=%q />",xml_escape(tostring(k)),xml_escape(tostring(v.page)))
    end
    if #tab > 0 then
        local file = io.open(auxfilename,"wb")
        file:write("<marker>\n")
        file:write(table.concat(tab,"\n"))
        file:write("\n</marker>")
        file:close()
    end
end

--- Load an XML file from the harddrive. filename is without path but including extension,
--- filetype is a string representing the type of file read, such as "layout" or "data".
--- The return value is a lua table representing the XML file.
---
--- The XML file
---
---     <?xml version="1.0" encoding="UTF-8"?>
---     <data>
---       <element attribute="whatever">
---         <subelement>text in subelement</subelement>
---       </element>
---     </data>
---
--- is represented by this Lua table:
---
---     XML = {
---       [1] = " "
---       [2] = {
---         [1] = " "
---         [2] = {
---           [1] = "text in subelement"
---           [".__parent"] = (pointer to the "element" tree, which is
---                            the second entry in the top level)
---           [".__local_name"] = "subelement"
---         },
---         [3] = " "
---         [".__parent"] = (pointer to the root element)
---         [".__local_name"] = "element"
---         ["attribute"] = "whatever"
---       },
---       [3] = " "
---       [".__local_name"] = "data"
---     },
function load_xml(filename,filetype,options)
    local path = kpse.find_file(filename)
    if not path then
        err("Can't find XML file %q. Abort.\n",filename or "?")
        return
    end
    log("Loading %s %q",filetype or "file",path)
    return luxor.parse_xml_file(path, options,kpse.find_file)
end

--- Place an object at a position given in scaled points (_x_ and _y_).
---
--- Parameter       | Description
--- ----------------|----------------------------------------------
--- nodelist        | The box to be placed
--- x               | The horizontal distance from the left edge in grid cells
--- y               | The vertical distance form the top edge in grid cells
--- rotate          | Rotation counter clockwise in degrees (0-360).
--- origin_x        | Origin X for rotation. Left is 0 and right is 100
--- origin_y        | Origin Y for rotation. Top is 0 and bottom is 100
function output_absolute_position(param)
    local nodelist = param.nodelist
    local x = param.x
    local y = param.y


    if node.has_attribute(nodelist,att_shift_left) then
        x = x - node.has_attribute(nodelist,att_shift_left)
        y = y - node.has_attribute(nodelist,att_shift_up)
    end

    if param.rotate then
        nodelist = rotate(nodelist,param.rotate, param.origin_x or 0, param.origin_y or 0)
    end

    local n = add_glue( nodelist ,"head",{ width = x })
    n = node.hpack(n)
    n = add_glue(n, "head", {width = y})
    n = node.vpack(n)
    n.width  = 0
    n.height = 0
    n.depth  = 0
    local tail = node.tail(pages[current_pagenumber].pagebox)
    tail.next = n
    n.prev = tail
end

--- Put the object (nodelist) on grid cell (x,y). If `allocate`=`true` then
--- mark cells as occupied.
---
--- Parameter       | Description
--- ----------------|----------------------------------------------
--- nodelist        | The box to be placed
--- x               | The horizontal distance from the left edge in grid cells
--- y               | The vertical distance form the top edge in grid cells
--- allocate        | Mark these cells as 'occupied'
--- area            | The area on which the object should be placed. Defaults to the page area.
--- valign          |
--- halign          |
--- allocate_matrix | For image-shapes
--- pagenumber      | The page the object should be placed
--- keepposition    | Move the local cursor?
--- grid            | The grid object. If not present, we use the default grid object
--- rotate          | Rotation counter clockwise in degrees (0-360).
--- origin_x        | Origin X for rotation. Left is 0 and right is 100
--- origin_y        | Origin Y for rotation. Top is 0 and bottom is 100
--- framewidth      | When frame=solid then this has the frame width
function output_at( param )
    _wd, _ht, _dp = node.dimensions(param.nodelist)
    if param.framewidth then
        _wd = _wd + param.framewidth
        _ht = _ht + param.framewidth
    end

    local outputpage = current_pagenumber
    if param.pagenumber then
        outputpage = param.pagenumber
    end
    local nodelist = param.nodelist
    if options.trace then
        nodelist = boxit(nodelist)
    end
    local x = param.x
    local y = param.y
    local allocate = param.allocate
    local allocate_matrix = param.allocate_matrix
    local area = param.area or default_areaname
    local valign = param.valign
    local halign = param.halign
    local keepposition = param.keepposition

    -- current_grid is important here, because it can be a group
    local r = param.grid or current_grid
    local wd = nodelist.width
    local ht = nodelist.height + nodelist.depth

    -- For grid allocation
    local width_gridcells   = r:width_in_gridcells_sp(wd)
    local height_gridcells  = r:height_in_gridcells_sp(ht)

    local delta_x, delta_y = r:position_grid_cell(x,y,area,wd,ht,valign,halign)

    if not delta_x then
        -- if delta_x is nil, delta_y has the error message
        err(delta_y)
        exit()
    end

    if node.has_attribute(nodelist,att_shift_left) then
        delta_x = delta_x - node.has_attribute(nodelist,att_shift_left)
        delta_y = delta_y - node.has_attribute(nodelist,att_shift_up)
    end


    local extra_crop = 0
    if param.framewidth then
        extra_crop = param.framewidth
    end

    r:setarea(delta_x - extra_crop,delta_y - extra_crop, _wd + extra_crop, _ht + extra_crop + _dp)

    --- We don't necessarily output things on a page, we can output them in a virtual page, called _group_.
    if current_group then
        -- Put the contents of the nodelist into the current group
        local group = groups[current_group]
        assert(group)

        local n = add_glue( nodelist ,"head",{ width = delta_x })
        n = node.hpack(n)
        n = add_glue(n, "head", {width = delta_y})
        n = node.vpack(n)

        if group.contents then
            -- There is already something in the group, we must add the new nodelist.
            -- The size of the new group: max(size of old group, size of new nodelist)
            local new_width, new_height
            new_width  = math.max(n.width, group.contents.width)
            new_height = math.max(n.height + n.depth, group.contents.height + group.contents.depth)

            group.contents.width  = 0
            group.contents.height = 0
            group.contents.depth  = 0

            local tail = node.tail(group.contents)
            tail.next = n
            n.prev = tail

            group.contents = node.vpack(group.contents)
            group.contents.width  = new_width
            group.contents.height = new_height
            group.contents.depth  = 0
        else
            -- group is empty
            group.contents = n
        end
        if allocate then
            r:allocate_cells(x,y,width_gridcells,height_gridcells,allocate_matrix)
        end
    else
        -- Put it on the current page
        if allocate then
            r:allocate_cells(x,y,width_gridcells,height_gridcells,allocate_matrix,area,keepposition)
        end
        if param.rotate then
            nodelist = rotate(nodelist,param.rotate, param.origin_x or 0, param.origin_y or 0)
        end

        local n = add_glue( nodelist ,"head",{ width = delta_x })
        n = node.hpack(n)
        n = add_glue(n, "head", {width = delta_y})
        n = node.vpack(n)
        n.width  = 0
        n.height = 0
        n.depth  = 0
        local tail = node.tail(pages[outputpage].pagebox)
        tail.next = n
        n.prev = tail

    end
end

--- Return the XML structure that is stored at &lt;pagetype>. For every pagetype
--- in the table "masterpages" the function is_pagetype() gets called.
-- pagenumber is for debugging purpose
function detect_pagetype(pagenumber)
    -- ugly hack. file global variables are a bad idea.
    xpath.push_state()
    local cp = current_pagenumber
    current_pagenumber = pagenumber
    local ret = nil
    for i=#masterpages,1,-1 do
        local pagetype = masterpages[i]
        if nextpage then
            if pagetype.name == nextpage then
                log("Page of type %q created (%d) - pagetype requested",pagetype.name or "<detect_pagetype>",pagenumber)
                nextpage = nil
                return pagetype.res
            end
        else
           if xpath.parse(nil,pagetype.is_pagetype,pagetype.ns) == true then
               log("Page of type %q created (%d)",pagetype.name or "<detect_pagetype>",pagenumber)
               ret = pagetype.res
               xpath.pop_state()
               current_pagenumber = cp
               return ret
           end
        end
    end
    err("Can't find correct page type!")
    current_pagenumber = cp
    xpath.pop_state()
    return false
end

--- _Must_ be called before something can be put on the page. Looks for hooks to be run before page creation.
function setup_page(pagenumber)
    trace("setup_page")
    if current_group then return end
    local thispage
    if pagenumber then
        thispage = pagenumber
        if pages[pagenumber] ~= nil then
            current_grid=pages[pagenumber].grid
            return
        end
    else
        if page_initialized_p(current_pagenumber) then
            current_grid=pages[current_pagenumber].grid
            return
        end

    end

    if not pagenumber then
        thispage = current_pagenumber
    end
    local trim_amount = tex.sp(options.trim or 0)
    local extra_margin
    if options.cutmarks or options.trimmarks then
        extra_margin = tex.sp("1cm") + trim_amount
    elseif trim_amount > 0 then
        extra_margin = trim_amount
    end
    local errorstring

    current_page, errorstring = page:new(options.pagewidth,options.pageheight, extra_margin, trim_amount,thispage)
    if not current_page then
        err("Can't create a new page. Is the page type (»PageType«) defined? %s",errorstring)
        exit()
    end
    current_grid = current_page.grid
    -- pages[current_pagenumber] = nil
    pages[thispage] = current_page

    local gridwidth, gridheight, nx, ny, dx, dy
    nx = options.gridcells_x
    ny = options.gridcells_y
    dx = options.gridcells_dx
    dy = options.gridcells_dy

    local pagetype = detect_pagetype(thispage)
    if pagetype == false then return false end

    for _,j in ipairs(pagetype) do
        local eltname = elementname(j)
        if type(element_contents(j))=="function" and eltname=="Margin" then
            element_contents(j)(current_page)
        elseif eltname=="Grid" then
            gridwidth  = element_contents(j).width
            gridheight = element_contents(j).height
            nx = element_contents(j).nx
            ny = element_contents(j).ny
            dx = element_contents(j).dx
            dx = element_contents(j).dy
        end
    end

    if gridwidth == nil and options.gridwidth ~= 0 then
        gridwidth = options.gridwidth
    end

    if gridheight == nil and options.gridheight ~= 0 then
        gridheight = options.gridheight
    end

    current_page.grid:set_width_height({wd = gridwidth, ht = gridheight, nx = nx, ny = ny, dx = dx, dy = dy })

    for _,j in ipairs(pagetype) do
        local eltname = elementname(j)
        if type(element_contents(j))=="function" and eltname=="Margin" then
            -- do nothing, done before
        elseif eltname=="Grid" then
            -- do nothing, done before
        elseif eltname=="AtPageCreation" then
            current_page.atpagecreation = element_contents(j)
        elseif eltname=="AtPageShipout" then
            current_page.AtPageShipout = element_contents(j)
        elseif eltname=="PositioningArea" then
            local name = element_contents(j).name
            current_grid.positioning_frames[name] = {}
            local current_positioning_area = current_grid.positioning_frames[name]
            -- we evaluate now, because the attributes in PositioningFrame can be page dependent.
            local tab  = dispatch(element_contents(j).layoutxml,element_contents(j).dataxml)
            for i,k in ipairs(tab) do
                current_positioning_area[#current_positioning_area + 1] = element_contents(k)
            end
        else
            err("Element name %q unknown (setup_page())",eltname or "<create_page>")
        end
    end

    local cp = current_page
    current_page = pages[thispage]
    if current_page.atpagecreation then
        pagebreak_impossible = true
        local cpn = current_pagenumber
        current_pagenumber = thispage
        current_grid = pages[thispage].grid
        dispatch(current_page.atpagecreation,nil)
        current_pagenumber = cpn
        pagebreak_impossible = false
    end

    local css_rules
    local cg = current_page.grid

    for k,v in pairs(cg.positioning_frames) do
        css_rules = publisher.css:matches({element = 'area', class=class,id=k}) or {}
        if css_rules["border-width"] then
            for i,frame in ipairs(v) do
                frame.draw = { color = "green"}
            end
        end
    end
    current_page = cp

end

--- Switch to the next frame in the given area.
function next_area( areaname, grid )
    grid = grid or current_grid
    local current_framenumber = grid:framenumber(areaname)
    if not current_framenumber then
        err("Cannot determine current area number (areaname=%q)",areaname or "(undefined)")
        return
    end
    if current_framenumber >= grid:number_of_frames(areaname) then
        new_page()
    else
        grid:set_framenumber(areaname, current_framenumber + 1)
    end
    grid:set_current_row(1,areaname)
end

--- Switch to a new page and shipout the current page.
--- This new page is only created if something is typeset on it.
function new_page()
    trace("publisher new_page")
    if pagebreak_impossible then
        return
    end
    local thispage = pages[current_pagenumber]
    if not thispage then
        -- new_page() is called without anything on the page yet
        setup_page()
        thispage = current_page
    end

    dothingsbeforeoutput(thispage)

    local n = node.vpack(pages[current_pagenumber].pagebox)
    if current_pagestore_name then
        local thispagestore = pagestore[current_pagestore_name]
        thispagestore[#thispagestore + 1] = n
    else
        tex.box[666] = n
        tex.shipout(666)
    end
    current_pagenumber = current_pagenumber + 1
    trace("page finished (new_page), setting current_pagenumber to %d",current_pagenumber)
end

-- a,b are both arrays of 6 numbers
function concat_transformation( a, b )
    local c = {}
    c[1] = a[1] * b[1] + a[2] * b[3]
    c[2] = a[1] * b[2] + a[2] * b[4]
    c[3] = a[3] * b[1] + a[4] * b[3]
    c[4] = a[3] * b[2] + a[4] * b[4]
    c[5] = a[5] * b[1] + a[6] * b[3] + b[5]
    c[6] = a[5] * b[2] + a[6] * b[4] + b[6]
    return c
end

-- Place a text in the background
function bgtext( box, textstring, angle, colorname, fontfamily, bgsize)
    local colorindex = colors[colorname].index
    local boxheight, boxwidth = box.height, box.width
    local angle_rad = -1 * math.rad(angle)
    local sin = math.sin(angle_rad)
    local cos = math.cos(angle_rad)

    a = paragraph:new()
    a:append(textstring, {fontfamily = fontfamily})
    a:set_color(colorindex)
    local textbox = node.hpack(a.nodelist)
    local rotated_height = sin * textbox.width  + cos * textbox.height
    local scale
    local shift_up = 0
    if bgsize == "contain" then
        scale = boxheight  / rotated_height
    else
        scale = 1
        shift_up = sp_to_bp((boxheight - rotated_height) / 2)
    end
    local rotated_width  = sin * textbox.height + cos * textbox.width
    local shift_right = sp_to_bp( (boxwidth - rotated_width * scale ) / 2)

    -- rotate: [cos θ sin θ −sin θ cos θ 0 0 ]
    local rotate_matrix = {   cos, sin, -1 * sin,   cos,           0, 0        }
    local scale_matrix  = { scale,   0,        0, scale,           0, 0        }
    local shift_matrix  = {     1,   0,        0,     1, shift_right, shift_up }
    local result_matrix
    result_matrix = concat_transformation(rotate_matrix,scale_matrix)
    result_matrix = concat_transformation(result_matrix,shift_matrix)
    local matrixstring = string.format("%g %g %g %g %d %g",math.round(result_matrix[1],3),math.round(result_matrix[2],3),math.round(result_matrix[3],3),math.round(result_matrix[4],3),math.round(result_matrix[5],3),math.round(result_matrix[6],3))
    local x = matrix( textbox, matrixstring,0,0 )
    x = node.hpack(x)
    x.width = 0
    x.height = 0
    box = node.insert_before(box,box,x)
    box = node.hpack(box)
    return box
end

-- Todo: size = contain, ...
function bgimage( box, imagename )
    local imginfo = new_image(imagename)
    local image = img.copy(imginfo.img)
    image.width = box.width
    image.height = box.height

    local imgnode = img.node(image)
    local x = node.hpack(imgnode)
    x.width = 0
    x.height = 0
    box = node.insert_before(box,box,x)
    box = node.hpack(box)
    return box
end

--- Draw a background behind the rectangular (box) object.
function background( box, colorname )
    if not colors[colorname] then
        warning("Background: Color %q is not defined",colorname)
        return box
    end
    local pdfcolorstring = colors[colorname].pdfstring
    local wd, ht, dp = sp_to_bp(box.width),sp_to_bp(box.height),sp_to_bp(box.depth)
    n = node.new("whatsit","pdf_literal")
    n.data = string.format("q %s 0 -%g %g %g re f Q",pdfcolorstring,dp,wd,ht + dp)
    n.mode = 0
    if node.type(box.id) == "hlist" then
        -- pdfliteral does not use up any space, so we can add it to the already packed box.
        n.next = box.list
        box.list.prev = n
        box.list = n
        return box
    else
        n.next = box
        box.prev = n
        n = node.hpack(n)
        return n
    end
end

--- Draw a frame around the given TeX box with color `colorname`.
--- The control points of the frame are
--- ![control points](img/roundedcorners.svg)

function frame(obj)
    local  box, colorname, width
    box          = obj.box
    colorname    = obj.colorname or "black"
    width        = obj.rulewidth or 0
    local b_b_r_radius = sp_to_bp(obj.b_b_r_radius)
    local b_t_r_radius = sp_to_bp(obj.b_t_r_radius)
    local b_t_l_radius = sp_to_bp(obj.b_t_l_radius)
    local b_b_l_radius = sp_to_bp(obj.b_b_l_radius)

    local b_b_r_radius_inner = math.round(math.max(sp_to_bp(obj.b_b_r_radius) - width / factor,0),3)
    local b_t_r_radius_inner = math.round(math.max(sp_to_bp(obj.b_t_r_radius) - width / factor,0),3)
    local b_t_l_radius_inner = math.round(math.max(sp_to_bp(obj.b_t_l_radius) - width / factor,0),3)
    local b_b_l_radius_inner = math.round(math.max(sp_to_bp(obj.b_b_l_radius) - width / factor,0),3)

    -- See http://en.wikipedia.org/wiki/File:Circle_and_cubic_bezier.svg
    -- http://en.wikipedia.org/wiki/Composite_B%C3%A9zier_curve
    -- 0.5522847498
    -- http://spencermortensen.com/articles/bezier-circle/
    -- 0.551915024494
    local circle_bezier = 0.551915024494
    local color = colors[colorname]
    if not color then
        err("Color %q is not defined",tostring(colorname))
        color = colors["black"]
    end
    local pdfcolorstring = color.pdfstring
    local wd, ht, dp = sp_to_bp(box.width),sp_to_bp(box.height),sp_to_bp(box.depth)
    local rw = math.round(width / factor,3) -- width of stroke

    -- outer boundary
    local x1, y1   = -rw + b_b_l_radius                     , -rw
    local x2, y2   =  rw + wd - b_b_r_radius                , -rw
    local x3, y3   =  rw + wd - circle_bezier * b_b_r_radius, -rw
    local x4, y4   =  rw + wd                               , -rw + circle_bezier * b_b_r_radius
    local x5, y5   =  rw + wd                               , -rw + b_b_r_radius
    local x6, y6   =  rw + wd                               ,  rw + ht - b_t_r_radius
    local x7, y7   =  rw + wd                               ,  rw + ht - circle_bezier * b_t_r_radius
    local x8, y8   =  rw + wd - circle_bezier * b_t_r_radius,  rw + ht
    local x9, y9   =  rw + wd - b_t_r_radius                ,  rw + ht
    local x10, y10 = -rw + b_t_l_radius                     ,  rw + ht
    local x11, y11 = -rw + circle_bezier * b_t_l_radius     ,  rw + ht
    local x12, y12 = -rw                                    ,  rw + ht - circle_bezier * b_t_l_radius
    local x13, y13 = -rw                                    ,  rw + ht - b_t_l_radius
    local x14, y14 = -rw                                    , -rw + b_b_l_radius
    local x15, y15 = -rw                                    , -rw + circle_bezier * b_b_l_radius
    local x16, y16 = -rw + circle_bezier * b_b_l_radius     , -rw

    x1,  y1  = math.round(x1,3),  math.round(y1,3)
    x2,  y2  = math.round(x2,3),  math.round(y2,3)
    x3,  y3  = math.round(x3,3),  math.round(y3,3)
    x4,  y4  = math.round(x4,3),  math.round(y4,3)
    x5,  y5  = math.round(x5,3),  math.round(y5,3)
    x6,  y6  = math.round(x6,3),  math.round(y6,3)
    x7,  y7  = math.round(x7,3),  math.round(y7,3)
    x8,  y8  = math.round(x8,3),  math.round(y8,3)
    x9,  y9  = math.round(x9,3),  math.round(y9,3)
    x10, y10 = math.round(x10,3), math.round(y10,3)
    x11, y11 = math.round(x11,3), math.round(y11,3)
    x12, y12 = math.round(x12,3), math.round(y12,3)
    x13, y13 = math.round(x13,3), math.round(y13,3)
    x14, y14 = math.round(x14,3), math.round(y14,3)
    x15, y15 = math.round(x15,3), math.round(y15,3)
    x16, y16 = math.round(x16,3), math.round(y16,3)


    -- inner boundary
    local xx1, yy1   =   b_b_l_radius_inner                      , 0
    local xx2, yy2   =   wd - b_b_r_radius_inner                 , 0
    local xx3, yy3   =   wd - circle_bezier * b_b_r_radius_inner , 0
    local xx4, yy4   =   wd                                      , circle_bezier * b_b_r_radius_inner
    local xx5, yy5   =   wd                                      , b_b_r_radius_inner
    local xx6, yy6   =   wd                                      , ht - b_t_r_radius_inner
    local xx7, yy7   =   wd                                      , ht - circle_bezier * b_t_r_radius_inner
    local xx8, yy8   =   wd - circle_bezier * b_t_r_radius_inner , ht
    local xx9, yy9   =   wd - b_t_r_radius_inner                 , ht
    local xx10, yy10 =   b_t_l_radius_inner                      , ht
    local xx11, yy11 =   circle_bezier * b_t_l_radius_inner      , ht
    local xx12, yy12 =   0                                       , ht - circle_bezier * b_t_l_radius_inner
    local xx13, yy13 =   0                                       , ht - b_t_l_radius_inner
    local xx14, yy14 =   0                                       , b_b_l_radius_inner
    local xx15, yy15 =   0                                       , circle_bezier * b_b_l_radius_inner
    local xx16, yy16 =   circle_bezier * b_b_l_radius_inner      , 0

    xx1,  yy1  = math.round(xx1,3),  math.round(yy1,3)
    xx2,  yy2  = math.round(xx2,3),  math.round(yy2,3)
    xx3,  yy3  = math.round(xx3,3),  math.round(yy3,3)
    xx4,  yy4  = math.round(xx4,3),  math.round(yy4,3)
    xx5,  yy5  = math.round(xx5,3),  math.round(yy5,3)
    xx6,  yy6  = math.round(xx6,3),  math.round(yy6,3)
    xx7,  yy7  = math.round(xx7,3),  math.round(yy7,3)
    xx8,  yy8  = math.round(xx8,3),  math.round(yy8,3)
    xx9,  yy9  = math.round(xx9,3),  math.round(yy9,3)
    xx10, yy10 = math.round(xx10,3), math.round(yy10,3)
    xx11, yy11 = math.round(xx11,3), math.round(yy11,3)
    xx12, yy12 = math.round(xx12,3), math.round(yy12,3)
    xx13, yy13 = math.round(xx13,3), math.round(yy13,3)
    xx14, yy14 = math.round(xx14,3), math.round(yy14,3)
    xx15, yy15 = math.round(xx15,3), math.round(yy15,3)
    xx16, yy16 = math.round(xx16,3), math.round(yy16,3)

    local n_clip = node.new("whatsit","pdf_literal")
    local rule_clip = {}
    rule_clip[#rule_clip + 1] = string.format("%g %g m",xx1,yy1)
    rule_clip[#rule_clip + 1] = string.format("%g %g l",xx2,yy2)
    rule_clip[#rule_clip + 1] = string.format("%g %g %g %g %g %g c", xx3,yy3, xx4,yy4, xx5, yy5 )
    rule_clip[#rule_clip + 1] = string.format("%g %g l",xx6, yy6)
    rule_clip[#rule_clip + 1] = string.format("%g %g %g %g %g %g c", xx7,yy7,xx8,yy8, xx9,yy9  )
    rule_clip[#rule_clip + 1] = string.format("%g %g l",xx10, yy10)
    rule_clip[#rule_clip + 1] = string.format("%g %g %g %g %g %g c", xx11,yy11,xx12,yy12, xx13,yy13  )
    rule_clip[#rule_clip + 1] = string.format("%g %g l",xx14,yy14 )
    rule_clip[#rule_clip + 1] = string.format("%g %g %g %g %g %g c W n ", xx15,yy15,xx16,yy16, xx1,yy1  )

    local n = node.new("whatsit","pdf_literal")
    local rule = {}

    -- We need to add q .. Q because the color would leak into the inner objects (#55)
    rule[#rule + 1] = string.format("q %s",pdfcolorstring)
    rule[#rule + 1] = string.format("%g w",rw)           -- rule width

    rule[#rule + 1] = string.format("%g %g m",xx1,yy1)
    rule[#rule + 1] = string.format("%g %g l",xx2,yy2)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", xx3,yy3, xx4,yy4, xx5, yy5 )
    rule[#rule + 1] = string.format("%g %g l",xx6, yy6)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", xx7,yy7,xx8,yy8, xx9,yy9  )
    rule[#rule + 1] = string.format("%g %g l",xx10, yy10)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", xx11,yy11,xx12,yy12, xx13,yy13  )
    rule[#rule + 1] = string.format("%g %g l",xx14,yy14 )
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c ", xx15,yy15,xx16,yy16, xx1,yy1  )

    rule[#rule + 1] = string.format("%g %g m",x1,y1)
    rule[#rule + 1] = string.format("%g %g l",x2,y2)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", x3,y3, x4,y4, x5, y5 )
    rule[#rule + 1] = string.format("%g %g l",x6, y6)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", x7,y7,x8,y8, x9,y9  )
    rule[#rule + 1] = string.format("%g %g l",x10, y10)
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", x11,y11,x12,y12, x13,y13  )
    rule[#rule + 1] = string.format("%g %g l",x14,y14 )
    rule[#rule + 1] = string.format("%g %g %g %g %g %g c", x15,y15,x16,y16, x1,y1  )
    if rw == 0 then
        rule[#rule + 1] = "n"
    else
        rule[#rule + 1] = "f* s"
    end
    rule[#rule + 1] = "Q"

    n.data      = table.concat(rule,      " ")
    n_clip.data = table.concat(rule_clip, " ")

    local pdf_save    = node.new("whatsit","pdf_save")
    local pdf_restore = node.new("whatsit","pdf_restore")

    node.insert_after(pdf_save,pdf_save,n)
    node.insert_after(n,n,n_clip)
    node.insert_after(n_clip,n_clip,box)

    local hvbox = node.hpack(pdf_save)
    hvbox.depth = 0
    node.insert_after(hvbox,node.tail(hvbox),pdf_restore)
    hvbox = node.vpack(hvbox)
    return hvbox
end

-- collect all spot colors used so far to create proper page resources
function usespotcolor(num)
    used_spotcolors[num] = true
end

-- Set the PDF pageresources for the current page.
function setpageresources()

    local gstateresource = string.format(" /ExtGState << /GS0 %d 0 R /GS1 %d 0 R >>", GS_State_OP_On, GS_State_OP_Off)
    local cropbox = ""

    if status.luatex_version < 79 then
        if #used_spotcolors > 0 then
            pdf.pageresources = "/ColorSpace << " .. spotcolors.getresource(used_spotcolors) .. " >>" .. gstateresource
        end
    else
        -- LuaTeX has setpageresources
        if #used_spotcolors > 0 then
            pdf.setpageresources("/ColorSpace << " .. spotcolors.getresource(used_spotcolors) .. " >>" .. gstateresource )
        else
            pdf.setpageresources(gstateresource)
        end
    end
end

-- return the fill and stroke color of the given colorstring
function fill_stroke_color( pdfcolor )
    local a,b = string.match(pdfcolor,"^(.*rg)(.*RG)")
    if a ~= nil then
        return a,b
    end
    a,b = string.match(pdfcolor,"^(.*k)(.*K)")
    if a ~= nil then
        return a,b
    end
    a,b = string.match(pdfcolor,"^(.*G)(.*g)")
    return a,b
end

--- Draw a circle
---
--- ![Control points in the circle](img/circlepoints.svg)
---
function circle( radiusx_sp, radiusy_sp, colorname,framecolorname,rulewidth_sp)
    if rulewidth_sp < 5 then
        framecolorname = colorname
    end
    radiusx_sp, radiusy_sp = sp_to_bp(radiusx_sp), sp_to_bp(radiusy_sp)
    rulewidth_sp = sp_to_bp(rulewidth_sp)
    local paint = node.new("whatsit","pdf_literal")
    local colentry = colors[colorname]
    if not colentry then
        err("Color %q unknown, reverting to black",colorname or "(no color name given)")
        colentry = colors["black"]
    end
    local framecolentry = colors[framecolorname]
    if not framecolentry then
        err("Color %q unknown, reverting to black",framecolorname or "(no color name given)")
        framecolentry = colors["black"]
    end

    local fillcolor, _    =  fill_stroke_color(colentry.pdfstring)
    local  _, bordercolor =  fill_stroke_color(framecolentry.pdfstring)
    local circle_bezier = 0.551915024494

    local shift_down, shift_right = -radiusy_sp, 0
    local x1 = math.round(   shift_right                                  ,3)
    local x2 = math.round(   shift_right + circle_bezier * radiusx_sp     ,3)
    local x3 = math.round(   shift_right + radiusx_sp                     ,3)
    local x8 = math.round(   shift_right - radiusx_sp * circle_bezier     ,3)
    local x9 = math.round(   shift_right - radiusx_sp                     ,3)

    local y1 = math.round(   shift_down                                           ,3)
    local y3 = math.round(   shift_down + radiusy_sp - radiusx_sp * circle_bezier ,3)
    local y4 = math.round(   shift_down + radiusy_sp                              ,3)
    local y5 = math.round(   shift_down + radiusy_sp + radiusy_sp * circle_bezier ,3)
    local y6 = math.round(   shift_down + 2*radiusy_sp                            ,3)

    local x4 = x3
    local x5 = x3
    local x6 = x2
    local x7 = x1
    local x10 = x9
    local x11 = x9
    local x12 = x8

    local y2 = y1
    local y7 = y6
    local y8 = y6
    local y9 = y5
    local y10 = y4
    local y11 = y3
    local y12 = y1

    local circle = {}
    circle[#circle + 1] = string.format("q %g w %s %s %g %g m", math.round(rulewidth_sp,3), bordercolor,fillcolor, shift_right, shift_down)
    circle[#circle + 1] = string.format("%g %g %g %g %g %g c",x2, y2, x3, y3, x4, y4)
    circle[#circle + 1] = string.format("%g %g %g %g %g %g c",x5, y5, x6, y6, x7, y7)
    circle[#circle + 1] = string.format("%g %g %g %g %g %g c",x8, y8, x9, y9, x10, y10)
    circle[#circle + 1] = string.format("%g %g %g %g %g %g c",x11, y11, x12, y12, x1, y1)
    circle[#circle + 1] = "b Q"
    paint.data = table.concat(circle, " ")
    local v = node.vpack(paint)
    return v
end

--- Create a colored area. width and height are in scaled points.
function box( width_sp,height_sp,colorname )
    local _width   = sp_to_bp(width_sp)
    local _height  = sp_to_bp(height_sp)

    local paint = node.new("whatsit","pdf_literal")
    local colentry = colors[colorname]
    if not colentry then
        err("Color %q unknown, reverting to black",colorname or "(no color name given)")
        colentry = colors["black"]
    end
    paint.data = string.format("q %s 1 0 0 1 0 0 cm 0 0 %g -%g re f Q",colentry.pdfstring,_width,_height)
    paint.mode = 0

    local h,v
    local hglue,vglue

    hglue = node.new("glue",0)
    hglue.spec = node.new("glue_spec")
    hglue.spec.width         = 0
    hglue.spec.stretch       = 2^16
    hglue.spec.stretch_order = 3
    h = node.insert_after(paint,paint,hglue)

    h = node.hpack(h,width_sp,"exactly")

    vglue = node.new(glue_node,0)
    vglue.spec = node.new("glue_spec")
    vglue.spec.width         = 0
    vglue.spec.stretch       = 2^16
    vglue.spec.stretch_order = 3
    v = node.insert_after(h,h,vglue)
    v = node.vpack(h,height_sp,"exactly")

    return v
end

--- After everything is ready for page shipout, we add debug output and crop marks if necessary
function dothingsbeforeoutput( thispage )

    if thispage and thispage.AtPageShipout then
        pagebreak_impossible = true
        dispatch(thispage.AtPageShipout)
        pagebreak_impossible = false
    end

    local current_page = pages[current_pagenumber]
    local r = current_page.grid
    -- r should be cg
    local cg = r
    local str
    find_user_defined_whatsits(pages[current_pagenumber].pagebox)
    local firstbox

    -- for spot colors, if necessary
    setpageresources()

    -- White background on page. Todo: Make color customizable and background optional.
    local wd = sp_to_bp(current_page.width)
    local ht = sp_to_bp(current_page.height)

    local x = 0 + current_page.grid.extra_margin
    local y = 0 + current_page.grid.extra_margin

    if options.trim then
        local trim_bp = sp_to_bp(options.trim)
        wd = wd + trim_bp * 2
        ht = ht + trim_bp * 2
        x = x - options.trim
        y = y - options.trim
    end

    -- White background
    firstbox = node.new("whatsit","pdf_literal")
    firstbox.data = string.format("q 0 0 0 0 k  1 0 0 1 0 0 cm %g %g %g %g re f Q",sp_to_bp(x), sp_to_bp(y),wd ,ht)
    firstbox.mode = 1

    if options.showgridallocation then
        local lit = node.new("whatsit","pdf_literal")
        lit.mode = 1
        lit.data = r:draw_gridallocation()

        if firstbox then
            local tail = node.tail(firstbox)
            tail.next = lit
            lit.prev = tail
        else
            firstbox = lit
        end
    end

    for framename,v in pairs(r.positioning_frames) do
        for _,frame in ipairs(v) do
            if frame.draw then
                local lit = node.new("whatsit","pdf_literal")
                lit.mode = 1
                lit.data = cg:draw_frame(frame)
                if firstbox then
                    local tail = node.tail(firstbox)
                    tail.next = lit
                    lit.prev = tail
                else
                    firstbox = lit
                end
            end
        end
    end

    if options.showgrid then
        local lit = node.new("whatsit","pdf_literal")
        lit.mode = 1
        lit.data = r:draw_grid()
        if firstbox then
            local tail = node.tail(firstbox)
            tail.next = lit
            lit.prev = tail
        else
            firstbox = lit
        end
    end
    r:trimbox(options.crop)

    if options.cutmarks then
        local lit = node.new("whatsit","pdf_literal")
        lit.mode = 1
        lit.data = r:cutmarks()
        if firstbox then
            local tail = node.tail(firstbox)
            tail.next = lit
            lit.prev = tail
        else
            firstbox = lit
        end
    end

    if options.trimmarks then
        local lit = node.new("whatsit","pdf_literal")
        lit.mode = 1
        lit.data = r:trimmarks()
        if firstbox then
            local tail = node.tail(firstbox)
            tail.next = lit
            lit.prev = tail
        else
            firstbox = lit
        end
    end

    if firstbox then
        local list_start = pages[current_pagenumber].pagebox
        pages[current_pagenumber].pagebox = firstbox
        node.tail(firstbox).next = list_start
        list_start.prev = node.tail(firstbox)
    end
end

--- Read the contents of the attribute `attname_english`. `typ` is one of
--- `string`, `number`, `length` and `boolean`.
--- `default` gives something that is to be returned if no attribute with this name is present.
function read_attribute( layoutxml,dataxml,attname,typ,default,context)
    local namespaces = layoutxml[".__ns"]
    if not layoutxml[attname] then
        return default -- can be nil
    end

    local val,num,ret
    val = string.gsub(layoutxml[attname],"{(.-)}", function (x)
        local ok, xp = xpath.parse_raw(dataxml,x,namespaces)
        if not ok then
            err(xp)
            return nil
        end
        return xpath.textvalue(xp[1])
        end)

    if typ=="xpath" then
        return xpath.textvalue(xpath.parse(dataxml,val,namespaces))
    elseif typ=="xpathraw" then
        local ok,tmp = xpath.parse_raw(dataxml,val,namespaces)
        if not ok then err(tmp)
            return nil
        else
            return tmp
        end
    elseif typ=="rawstring" then
        return tostring(val)
    elseif typ=="string" then
        return tostring(translate_value(val,context) or default)
    elseif typ=="number" then
        return tonumber(val)
        -- something like "3pt"
    elseif typ=="length" then
        return val
        -- same as before, just changed to scaled points
    elseif typ=="length_sp" then
        num = tonumber(val or default)
        if num then -- most likely really a number, we need to multiply with grid width
            ret = current_grid:width_sp(num)
        else
            ret = val
        end
        return tex.sp(ret)
    elseif typ=="height_sp" then
        num = tonumber(val or default)
        if num then -- most likely really a number, we need to multiply with grid height
            ret = current_page.grid.gridheight * num
        else
            ret = val
        end
        return tex.sp(ret)
    elseif typ=="width_sp" then
        num = tonumber(val or default)
        if num then -- most likely really a number, we need to multiply with grid width
            ret = current_page.grid:width_sp(num)
        else
            ret = val
        end
        return tex.sp(ret)
    elseif typ=="boolean" then
        if val then
            val = translate_value(val,context)
        else
            val = default
        end
        if val=="yes" then
            return true
        elseif val=="no" then
            return false
        end
        return nil
    elseif typ=="booleanorlength" then
        if val then
            val = translate_value(val,context)
        else
            val = default
        end
        if val=="yes" then
            return true
        elseif val=="no" then
            return false
        else
            return tex.sp(val)
        end
    else
        warning("read_attribute (2): unknown type: %s",type(val))
    end
    return val
end

-- Return the element name of the given element (elt)
function elementname(elt)
    return elt.elementname
end

--- Return the contents of an entry from the `dispatch()` function call.
function element_contents( elt )
    return elt.contents
end

-- To split the textblock in pieces
local marker
marker = node.new("whatsit","user_defined")
marker.user_id = user_defined_marker
marker.type = 100  -- type 100: "value is a number"
marker.value = 1

--- Convert `<b>`, `<u>` and `<i>` in text to publisher recognized elements.
function parse_html( elt, parameter )
    local a = paragraph:new()
    local bold,italic,underline,allowbreak
    if parameter then
        if parameter.underline then
            underline = 1
        end
        if parameter.bold then
            bold = 1
        end
        if parameter.italic then
            italic = 1
        end
        allowbreak = parameter.allowbreak
    end

    if elt[".__local_name"] then
        local eltname = string.lower(elt[".__local_name"])
        if eltname == "table" then
            -- Evil. Build a table in Publisher-mode and send it to the output
            local x = parse_html_table(elt)
            x = node.hpack(x)
            node.set_attribute(x,att_dont_format,1)
            return x
        elseif eltname == "b" or eltname == "strong" then
            bold = 1
        elseif eltname == "i" then
            italic = 1
        elseif eltname == "u" then
            underline = 1
            if elt.class then
                local css_rules = css:matches({element = 'u', class=elt.class}) or {}
                if css_rules["border-style"] == "dashed" then
                    underline = 2
                end
            end
        elseif eltname == "sub" then
            for i=1,#elt do
                if type(elt[i]) == "string" then
                    a:script(elt[i],1,{fontfamily = 0, bold = bold, italic = italic, underline = underline })
                elseif type(elt[i]) == "table" then
                    a:script(parse_html(elt[i]),1,{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                end
            end
            elt = {}
        elseif eltname == "sup" then
            for i=1,#elt do
                if type(elt[i]) == "string" then
                    a:script(elt[i],2,{fontfamily = 0, bold = bold, italic = italic, underline = underline })
                elseif type(elt[i]) == "table" then
                    a:script(parse_html(elt[i]),2,{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                end
            end
            elt = {}
        elseif eltname == "ul" then
            for i=1,#elt do
                if type(elt[i]) == "string" then
                    -- ignore
                elseif type(elt[i]) == "table" then
                    -- remove last br in the list
                    if  elt[i][#elt[i]] and elt[i][#elt[i]][".__name"] == "br" then
                        elt[i][#elt[i]] = nil
                    end
                    a:append(node.copy(marker))
                    local bul = bullet_hbox(tex.sp("2.5mm"))
                    a:append(bul)
                    a:append(parse_html(elt[i]),{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                    a:append("\n",{})
                end
            end
            a:append(node.copy(marker))
            return a
        elseif eltname == "ol" then
            local counter = 0
            for i=1,#elt do
                if type(elt[i]) == "string" then
                    -- ignore
                elseif type(elt[i]) == "table" then
                    -- remove last br in the list
                    if elt[i][#elt[i]] and elt[i][#elt[i]][".__name"] == "br" then
                        elt[i][#elt[i]] = nil
                    end
                    counter = counter + 1
                    a:append(node.copy(marker))
                    local num = number_hbox(counter,tex.sp("4mm"))
                    a:append(num)
                    a:append(parse_html(elt[i]),{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                    a:append("\n",{})
                end
            end
            a:append(node.copy(marker))
            return a
        elseif eltname == "a" then
            if elt.href == nil then
                warning("html a link has no href")
                for i=1,#elt do
                    if type(elt[i]) == "string" then
                        a:append(elt[i],{fontfamily = 0, bold = bold, italic = italic, underline = underline })
                    elseif type(elt[i]) == "table" then
                        a:append(parse_html(elt[i]),{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                    end
                end
            else
                local ai = node.new("action")
                ai.action_type = 3
                ai.data = string.format("/Subtype/Link/A<</Type/Action/S/URI/URI(%s)>>",elt.href)
                local stl = node.new("whatsit","pdf_start_link")
                stl.action = ai
                stl.width = -1073741824
                stl.height = -1073741824
                stl.depth = -1073741824
                a:append(stl)
                for i=1,#elt do
                    if type(elt[i]) == "string" then
                        a:append(elt[i],{fontfamily = 0, bold = bold, italic = italic, underline = underline })
                    elseif type(elt[i]) == "table" then
                        a:append(parse_html(elt[i]),{fontfamily = 0, bold = bold, italic = italic, underline = underline})
                    end
                end
                local enl = node.new("whatsit","pdf_end_link")
                a:append(enl)
            end
            return a
        elseif string.match(eltname,"^[bB][rR]$") then
            a:append("\n",{})
        elseif #elt == 0 then
            -- dummy: insert U+200B ZERO WIDTH SPACE which results in a strut
            a:append("\xE2\x80\x8B")
        end
    end
    -- Recurse into the children...
    for i=1,#elt do
        local typ = type(elt[i])
        local options = {fontfamily = 0, bold = bold, italic = italic, underline = underline, allowbreak = allowbreak }
        if typ == "string" or typ == "number" or typ == "boolean" then
            a:append(elt[i],options)
        elseif typ == "table" then
            local tmp = parse_html(elt[i],options)
            a:append(tmp)
        end
    end

    return a
end

function parse_html_table(elt)
    local tbl
    for i=1,#elt do
        local thiselt = elt[i]
        if type(thiselt) == "table" then
            if thiselt[".__local_name"] == "tbody" then
                tbl = parse_html_tbody(thiselt)
            end
        end
    end
    local tabular = publisher.tabular:new()
    tabular.width = xpath.get_variable("__maxwidth")
    tabular.tab = tbl
    local fontname = "text"
    local fontfamily = publisher.fonts.lookup_fontfamily_name_number[fontname]
    local save_fontfamily = publisher.current_fontfamily
    publisher.current_fontfamily = fontfamily

    if fontfamily == nil then
        err("Fontfamily %q not found.",fontname or "???")
        fontfamily = 1
    end

    tabular.fontfamily = fontfamily
    tabular.options ={ ht_max=99999*2^16 }
    tabular.padding_left   = 0
    tabular.padding_top    = 0
    tabular.padding_right  = 0
    tabular.padding_bottom = 0
    tabular.colsep         = tex.sp("2pt")
    tabular.rowsep         = 0

    local n = tabular:make_table()
    return n[1]
end

function parse_html_tbody(body)
    local ret = {}
    for j=1,#body do
        local tr = body[j]
        if type(tr) == "table" then
            if tr[".__local_name"] ~= "tr" then
                err("not a table row")
                return
            end
            ret[#ret + 1] = parse_html_tr(tr)
        end
    end
    return ret
end

function parse_html_tr(tr)
    local ret = {}
    for j=1,#tr do
        local td = tr[j]
        if type(td) == "table" then
            if td[".__local_name"] ~= "td" and td[".__local_name"] ~= "th" then
                err("not a table cell")
                return
            end
            local tmp = {}
            for i=1,#td do
                if type(td[i]) == "table" then
                    local a = parse_html(td[i])
                    set_fontfamily_if_necessary(a.nodelist,current_fontfamily)
                    if td[".__local_name"] == "th" then
                        a.textformat = "__centered"
                        a:add_italic_bold(a.nodelist, {bold = 1})
                    end
                    local par = { elementname = "Paragraph" , contents = a }
                    tmp[#tmp + 1] = { elementname = "Paragraph" , contents = a }
                end
            end
            ret[#ret + 1] = { elementname = "Td", contents = tmp}
        end
    end
    return { elementname = "Tr", contents = ret}
end


--- Look for `user_defined` at end of page (shipout) and runs actions encoded in them.
function find_user_defined_whatsits( head )
    local fun
    while head do
        if head.id == vlist_node or head.id==hlist_node then
            -- We need to recurse into the boxes. The colors used there must be kept.
            -- Todo: use a variable that is global for this function. (do local x ; function ... end end)
            find_user_defined_whatsits(head.list)
        elseif head.id==whatsit_node then
            if head.subtype == user_defined_whatsit then
                -- action
                if head.user_id == user_defined_addtolist then
                    -- the value is the index of the hash of user_defined_functions
                    fun = user_defined_functions[head.value]
                    fun()
                    -- use and forget
                    user_defined_functions[head.value] = nil
                    -- bookmark
                elseif head.user_id == user_defined_bookmark then
                    local level,openclose,dest,str =  string.match(head.value,"([^+]*)+([^+]*)+([^+]*)+(.*)")
                    level = tonumber(level)
                    local open_p
                    if openclose == "1" then
                        open_p = true
                    else
                        open_p = false
                    end
                    local i = 1
                    local current_bookmark_table = bookmarks -- level 1 == top level
                    -- create levels if necessary
                    while i < level do
                        if #current_bookmark_table == 0 then
                            current_bookmark_table[1] = {}
                            err("No bookmark given for this level (%d)!",level)
                        end
                        current_bookmark_table = current_bookmark_table[#current_bookmark_table]
                        i = i + 1
                    end
                    current_bookmark_table[#current_bookmark_table + 1] = {name = str, destination = dest, open = open_p}
                elseif head.user_id == user_defined_mark then
                    local marker = head.value
                    markers[marker] = { page = current_pagenumber }
                elseif head.user_id == user_defined_mark_append then
                    local marker = head.value
                    if markers[marker] == nil then
                        markers[marker] = { page = tostring(current_pagenumber) }
                    else
                        markers[marker]["page"] = tostring(markers[marker]["page"]) .. "," ..  tostring(current_pagenumber)
                    end
                end
            end
        end
        head = head.next
    end
    return colors_used
end

--- Node(list) creation
--- -------------------


rightskip = node.new("glue_spec")
rightskip.width = 0
rightskip.stretch = 1 * 2^16
rightskip.stretch_order = 3

leftskip = node.new("glue_spec")
leftskip.width = 0
leftskip.stretch = 1 * 2^16
leftskip.stretch_order = 3

--- Return the larger glue(spec) values
function bigger_glue_spec( a,b )
    if a.stretch_order > b.stretch_order then return a end
    if b.stretch_order > a.stretch_order then return b end
    if a.stretch > b.stretch then return a end
    if b.stretch > a.stretch then return b end
    if a.width > b.width then return a else return b end
end


function addstrut(nodelist,where)
    local strutheight = 0
    local head = nodelist
    while head do
        if head.id == hlist_node then
            strutheight = head.height
            if node.has_attribute(head,att_dont_format) then
                -- 0.25 is the depth of the line, and hopefully
                -- this is the highest thing in the line
                head.shift = 0.25 * head.height
            end
        end
        head = head.next

    end
    head = nodelist
    while head do
        if node.has_attribute(head, att_fontfamily) then
            break
        end
        head = head.next
    end
    local fontfamily

    if head == nil then
        fontfamily = nil
    else
        fontfamily = node.has_attribute(head, att_fontfamily)
    end

    if fontfamily == nil or fontfamily == 0 then
        fontfamily = fonts.lookup_fontfamily_name_number["text"]
    end

    local fi = fonts.lookup_fontfamily_number_instance[fontfamily]
    strutheight = math.max(fi.baselineskip, strutheight)
    local strut
    strut = add_rule(nodelist,"head",{height = 0.75 * strutheight, depth = 0.25 * strutheight, width = 0 })
    if where then
        node.set_attribute(strut,att_origin,where)
    end
    return strut
end

--- Create a `\hbox`. Return a nodelist. Parameter is one of
---
--- * languagecode
--- * bold (bold)
--- * italic (italic)
--- * underline
function mknodes(str,fontfamily,parameter)
    -- instance is the internal fontnumber
    parameter = parameter or {}
    local instance
    local instancename
    local languagecode = parameter.languagecode or defaultlanguage
    if parameter.bold == 1 then
        if parameter.italic == 1 then
            instancename = "bolditalic"
        else
            instancename = "bold"
        end
    elseif parameter.italic == 1 then
        instancename = "italic"
    else
        instancename = "normal"
    end

    if fontfamily and fontfamily > 0 then
        instance = fonts.lookup_fontfamily_number_instance[fontfamily][instancename]
    else
        instance = 1
    end

    local tbl = font.getfont(instance)
    local space   = tbl.parameters.space
    local shrink  = tbl.parameters.space_shrink
    local stretch = tbl.parameters.space_stretch
    local match = unicode.utf8.match

    local head, last, n
    local char

    -- if it's an empty string, we make a zero-width rule
    if string.len(str) == 0 then
        -- a space char can have a width, so we return a zero width something
        local strut = add_rule(nil,"head",{height = 1 * factor, depth = 0, width = 0 })
        return strut
    end
    local lastitemwasglyph
    local newline = 10
    local breakatspace = true
    if parameter.allowbreak and not string.find(parameter.allowbreak, " ") then
        breakatspace = false
    end
    -- There is a string with utf8 chars
    for s in string.utfvalues(str) do
        local char = unicode.utf8.char(s)
        -- If the next char is a newline (&#x0A;) a \\ is inserted
        if s == newline then
            -- This is to enable hyphenation again. When we add a rule right after a word
            -- hyphenation is disabled. So we insert a penalty of 10k which should not do
            -- harm. Perhaps there is a better solution, but this seems to work OK.
            local dummypenalty
            dummypenalty = node.new("penalty")
            dummypenalty.penalty = 10000
            head,last = node.insert_after(head,last,dummypenalty)

            local strut
            strut = add_rule(nil,"head",{height = 8 * factor, depth = 3 * factor, width = 0 })
            head,last = node.insert_after(head,last,strut)

            local p1,g,p2
            p1 = node.new("penalty")
            p1.penalty = 10000

            g = node.new("glue")
            g.spec = node.new("glue_spec")
            g.spec.stretch = 2^16
            g.spec.stretch_order = 2

            p2 = node.new("penalty")
            p2.penalty = -10000

            head,last = node.insert_after(head,last,p1)
            head,last = node.insert_after(head,last,g)
            head,last = node.insert_after(head,last,p2)
        elseif match(char,"^%s$") and last and last.id == glue_node and not node.has_attribute(last,att_tie_glue,1) then
            -- double space, use the bigger glue
            local tmp = node.new(glue_spec_node)
            tmp.width   = space
            tmp.shrink  = shrink
            tmp.stretch = stretch
            last.spec = bigger_glue_spec(last.spec,tmp)
        elseif s == 160 then -- non breaking space U+00A0
            n = node.new("penalty")
            n.penalty = 10000

            head,last = node.insert_after(head,last,n)

            n = node.new("glue")
            n.spec = node.new("glue_spec")
            n.spec.width   = space
            n.spec.shrink  = shrink
            n.spec.stretch = stretch

            node.set_attribute(n,att_tie_glue,1)

            head,last = node.insert_after(head,last,n)

            -- can be 1 == solid or 2 == dashed
            if parameter.underline then
                node.set_attribute(n,att_underline,parameter.underline)
            end
            node.set_attribute(n,att_fontfamily,fontfamily)
        elseif s == 173 then -- soft hyphen
            -- The soft hyphen is used in server-mode /v0/format
            n = node.new(penalty_node)
            n.penalty = 10000
            head, last = node.insert_after(head,last,n)

            n = node.new(disc_node)
            node.set_attribute(n,att_keep,1)
            head, last = node.insert_after(head,last,n)

            n = node.new(penalty_node)
            n.penalty = 10000
            head, last = node.insert_after(head,last,n)

            n = node.new(glue_node)
            n.spec = node.new(glue_spec_node)
            head, last = node.insert_after(head,last,n)
        elseif s == 8203 then
            -- U+200B ZERO WIDTH SPACE inserted in parse_html
            head = addstrut(head)
            last = node.tail(head)
        -- anchor is necessary. Otherwise à (C3A0) would match A0 - %s
        elseif match(char,"^%s$") then -- Space
            if breakatspace == false then
                n = node.new("penalty")
                n.penalty = 10000

                head,last = node.insert_after(head,last,n)

            end
            -- ; and : should have the possibility to break easily if a space follows
            if last and last.id == glyph_node and ( last.char == 58 or last.char == 59) then
                n = node.new("penalty")
                n.penalty = 0
                head,last = node.insert_after(head,last,n)
            end
            n = node.new("glue")
            n.spec = node.new("glue_spec")
            n.spec.width   = space
            n.spec.shrink  = shrink
            n.spec.stretch = stretch

            if breakatspace == false then
                node.set_attribute(n,att_tie_glue,1)
            end

            if parameter.underline then
                node.set_attribute(n,att_underline,parameter.underline)
            end
            node.set_attribute(n,att_fontfamily,fontfamily)

            head,last = node.insert_after(head,last,n)
        else
            -- A regular character?!?
            n = node.new("glyph")
            n.font = instance
            n.subtype = 1
            n.char = s
            n.lang = languagecode
            n.uchyph = 1
            n.left = parameter.left or tex.lefthyphenmin
            n.right = parameter.right or tex.righthyphenmin
            node.set_attribute(n,att_fontfamily,fontfamily)
            if parameter.bold == 1 then
                node.set_attribute(n,att_bold,1)
            end
            if parameter.italic == 1 then
                node.set_attribute(n,att_italic,1)
            end
            if parameter.underline then
                node.set_attribute(n,att_underline,parameter.underline)
            end
            if last and last.id == glyph_node then
                lastitemwasglyph = true
            end

            head,last = node.insert_after(head,last,n)
            -- Some characters must be treated in a special way.
            -- Hyphens must be separated from words:
            if ( n.char == 45 or n.char == 8211) and lastitemwasglyph then
                local pen = node.new("penalty")
                pen.penalty = 10000
                head = node.insert_before(head,last,pen)
                local disc = node.new("disc")
                head,last = node.insert_after(head,last,disc)
                local g = node.new(glue_node)
                g.spec = node.new(glue_spec_node)
                head,last = node.insert_after(head,last,g)
            elseif parameter.allowbreak and string.find(parameter.allowbreak, char,1,true) then
                -- allowbreak lists characters where the publisher may break lines
                local pen = node.new("penalty")
                pen.penalty = 0
                head,last = node.insert_after(head,last,pen)
            end
        end
    end

    if not head then
        -- This should never happen.
        warning("No head found")
        return node.new("hlist")
    end
    return head
end

-- head_or_tail = "head" oder "tail" (default: tail). Return new head (perhaps same as nodelist)
function add_rule( nodelist,head_or_tail,parameters)
    parameters = parameters or {}

    local n=node.new("rule")
    n.width  = parameters.width
    n.height = parameters.height
    n.depth  = parameters.depth
    if not nodelist then return n end

    if head_or_tail=="head" then
        nodelist = node.insert_before(nodelist,nodelist,n)
        return nodelist
    else
        local last=node.slide(nodelist)
        last.next = n
        n.prev = last
        return nodelist,n
    end
    assert(false,"never reached")
end

--- Return a hbox with width `labelwidth`
function bullet_hbox( labelwidth )
    local bullet, pre_glue, post_glue
    bullet = mknodes("•",nil,{})

    pre_glue = node.new("glue")
    pre_glue.spec = node.new("glue_spec")
    pre_glue.spec.stretch = 65536
    pre_glue.spec.stretch_order = 3
    pre_glue.next = bullet

    post_glue = node.new("glue")
    post_glue.spec = node.new("glue_spec")
    post_glue.spec.width = 4 * 2^16
    post_glue.prev = bullet
    bullet.next = post_glue
    local bullet_hbox = node.hpack(pre_glue,labelwidth,"exactly")

    if options.trace then
        boxit(bullet_hbox)
    end
    node.set_attribute(bullet_hbox,att_indent,labelwidth)
    node.set_attribute(bullet_hbox,att_rows,-1)
    return bullet_hbox
end

--- Return a hbox with width `labelwidth`
function number_hbox( num, labelwidth )
    local pre_glue, post_glue
    local digits = mknodes( tostring(num) .. ".",nil,{})
    pre_glue = node.new("glue")
    pre_glue.spec = node.new("glue_spec")
    pre_glue.spec.stretch = 65536
    pre_glue.spec.stretch_order = 3
    pre_glue.next = digits

    post_glue = node.new("glue")
    post_glue.spec = node.new("glue_spec")
    post_glue.spec.width = 4 * 2^16
    post_glue.prev = node.tail(digits)
    node.tail(digits).next = post_glue
    local digit_hbox = node.hpack(pre_glue,labelwidth,"exactly")

    if options.trace then
        boxit(digit_hbox)
    end
    node.set_attribute(digit_hbox,att_indent,labelwidth)
    node.set_attribute(digit_hbox,att_rows,-1)
    return digit_hbox
end


-- Add a glue to the front or tail of the given nodelist. `head_or_tail` is
-- either the string `head` or `tail`. `parameter` is a table with the keys
-- `width`, `stretch` and `stretch_order`. If the nodelist is nil, a simple
-- node list consisting of a glue will be created.
function add_glue( nodelist,head_or_tail,parameter)
    parameter = parameter or {}

    local n=node.new("glue", parameter.subtype or 0)
    n.spec = node.new("glue_spec")
    n.spec.width         = parameter.width
    n.spec.stretch       = parameter.stretch
    n.spec.stretch_order = parameter.stretch_order

    if nodelist == nil then return n end

    if head_or_tail=="head" then
        n.next = nodelist
        nodelist.prev = n
        return n
    else
        local last=node.slide(nodelist)
        last.next = n
        n.prev = last
        return nodelist,n
    end
    assert(false,"never reached")
end

function make_glue( parameter )
    local n = node.new("glue")
    n.spec = node.new("glue_spec")
    n.spec.width         = parameter.width
    n.spec.stretch       = parameter.stretch
    n.spec.stretch_order = parameter.stretch_order
    return n
end

function finish_par( nodelist,hsize,parameters )
    assert(nodelist)
    node.slide(nodelist)

    if not parameters.disable_hyphenation then
        lang.hyphenate(nodelist)
    end
    local n = node.new("penalty")
    node.set_attribute(n,att_origin,origin_finishpar)
    n.penalty = 10000
    local last = node.slide(nodelist)

    last.next = n
    n.prev = last
    last = n

    n = node.kerning(nodelist)
    -- FIXME: why do I call node.ligaturing()? I don't have any ligatures anyway
    -- n = node.ligaturing(n)
    -- 15 is a parfillskip
    n,last = add_glue(n,"tail",{ subtype = 15, width = 0, stretch = 2^16, stretch_order = 2})
end

function fix_justification( nodelist,alignment,parent)
    local head = nodelist
    while head do
        if head.id == 0 then -- hlist

            -- we are on a line now. We assume that the spacing needs correction.
            -- The goal depends on the current line (parshape!)
            local goal
            if head.width == 1 then
                goal, _, _ = node.dimensions(head.glue_set, head.glue_sign, head.glue_order, head.head)
            else
                goal = head.width
            end
            local font_before_glue

            -- The following code is problematic, in tabular material. This is my older comment
            -- There was code here (39826d4c5 and before) that changed
            -- the glue depending on the font before that glue. That
            -- was problematic, because LuaTeX does not copy the
            -- altered glue_spec node on copy_list (in paragraph:format())
            -- which, when reformatted, gets a complaint by LuaTeX about
            -- infinite shrinkage in a paragraph

            -- a new glue spec node - we must not(!) alter the current glue spec
            -- because this list is copied in paragraph:format()
            local spec_new

            for n in node.traverse(head.head) do
                if n.id == glyph_node then
                    font_before_glue = n.font
                elseif n.id == glue_node then
                    if n.subtype==0 and font_before_glue and n.spec.width > 0 and head.glue_sign == 1 then
                        local fonttable = font.fonts[font_before_glue]
                        if not fonttable then fonttable = font.fonts[1] err("Some font not found") end
                        spec_new = node.new("glue_spec")
                        spec_new.width = fonttable.parameters.space
                        spec_new.shrink_order = head.glue_order
                        n.spec = spec_new
                    end
                end
            end

            if alignment == "rightaligned" then

                local list_start = head.head
                local rightskip_node = node.tail(head.head)
                local parfillskip

                -- first we remove everything between the rightskip and the
                -- last non-glue/non-penalty item
                -- the glues might contain "plus 1 fill" and the penalties are not
                -- useful
                local tmp = rightskip_node.prev
                while tmp and ( tmp.id == glue_node or tmp.id == penalty_node ) do
                    tmp = tmp.prev
                    head.head = node.remove(head.head,tmp.next)
                end

                local wd = node.dimensions(head.glue_set, head.glue_sign, head.glue_order,head.head)

                local leftskip_node = node.new("glue")
                leftskip_node.spec = node.new("glue_spec")
                leftskip_node.spec.width = goal - wd
                head.head = node.insert_before(head.head,head.head,leftskip_node)
            end

            if alignment == "centered" then
                local list_start = head.head
                local rightskip_node = node.tail(head.head)
                local parfillskip

                -- first we remove everything between the rightskip and the
                -- last non-glue/non-penalty item
                -- the glues might contain "plus 1 fill" and the penalties are not
                -- useful
                local tmp = rightskip_node.prev
                while tmp and ( tmp.id == glue_node or tmp.id == penalty_node ) do
                    tmp = tmp.prev
                    if tmp then
                        head.head = node.remove(head.head,tmp.next)
                    end
                end

                local wd = node.dimensions(head.glue_set, head.glue_sign, head.glue_order,head.head)

                local leftskip_node = node.new("glue")
                leftskip_node.spec = node.new("glue_spec")
                leftskip_node.spec.width = ( goal - wd ) / 2
                head.head = node.insert_before(head.head,head.head,leftskip_node)
            end
        elseif head.id == 1 then -- vlist
            fix_justification(head.head,alignment,head)
        end
        head = head.next
    end
    return nodelist
end

local function check_if_a_line_exeeds(nodelist,wd,glue_set,glue_sign,glue_order)
    local head = nodelist
    while head do
        if head.id == vlist_node then
            return check_if_a_line_exeeds(head.head,wd,glue_set,glue_sign,glue_order)
        elseif head.id == hlist_node then
            local width = node.dimensions(glue_set,glue_sign,glue_order,head.head)
            if width > wd then
                return true
            end
        end
        head = head.next
    end
    return false
end

function do_linebreak( nodelist,hsize,parameters )
    assert(nodelist,"No nodelist found for line breaking.")
    parameters = parameters or {}
    finish_par(nodelist,hsize,parameters)

    local pdfignoreddimen
    pdfignoreddimen    = -65536000


    local default_parameters = {
        hsize = hsize,
        emergencystretch = 0.1 * hsize,
        hyphenpenalty = 0,
        linepenalty = 10,
        pretolerance = 0,
        tolerance = 2000,
        doublehyphendemerits = 1000,
        pdfeachlineheight = pdfignoreddimen,
        pdfeachlinedepth  = pdfignoreddimen,
        pdflastlinedepth  = pdfignoreddimen,
        pdfignoreddimen   = pdfignoreddimen,
    }

    setmetatable(parameters,{__index=default_parameters})

    -- Try to break the paragraph until there is no line
    -- longer than expected
    local j
    local c = 0
    while true do
        j = tex.linebreak(node.copy_list(nodelist),parameters)
        if not check_if_a_line_exeeds(j,hsize,j.glue_set, j.glue_sign,j.glue_order) then
            break
        end
        default_parameters.emergencystretch = default_parameters.emergencystretch + 0.1 * hsize
        c = c + 1
        if c > 9 then
            break
        end
        node.flush_list(j)
    end
    node.flush_list(nodelist)

    -- Adjust line heights. Always take the largest font in a row.
    local head = j
    local maxlineheight
    local fam
    while head do
        if head.id == hlist_node then -- hlist
            local lineheight
            maxlineheight = 0
            local head_list = head.list
            while head_list do
                lineheight = lineheight or node.has_attribute(head_list,att_lineheight)
                -- There could be a hlist (HTML table for example) in the line
                if head_list.id == hlist_node or head_list.id == vlist_node then
                    maxlineheight = math.max(head_list.height,maxlineheight)
                else
                    fam = node.has_attribute(head_list,att_fontfamily)
                    if fam then
                        -- Is this necessary anymore? FIXME
                        if fam == 0 then fam = 1 end
                        maxlineheight = math.max(fonts.lookup_fontfamily_number_instance[fam].baselineskip,maxlineheight)
                    end
                end
                head_list = head_list.next
            end
            if lineheight and lineheight > 0.75 * maxlineheight then
                head.height = lineheight
                head.depth  = 0.25 * maxlineheight
            else
                head.height = 0.75 * maxlineheight
                head.depth  = 0.25 * maxlineheight
            end
        end
        head = head.next
    end

    return node.vpack(j)
end

function create_empty_hbox_with_width( wd )
    local n=node.new("glue")
    n.spec = node.new("glue_spec")
    n.spec.width         = 0
    n.spec.stretch       = 2^16
    n.spec.stretch_order = 3
    n = node.hpack(n,wd,"exactly")
    return n
end

do
    local destcounter = 0
    -- Create a pdf anchor (dest object). It returns a whatsit node and the
    -- number of the anchor, so it can be used in a pdf link or an outline.
    function mkdest()
        destcounter = destcounter + 1
        local d = node.new("whatsit","pdf_dest")
        d.named_id = 0
        d.dest_id = destcounter
        d.dest_type = 3
        return d, destcounter
    end
end

-- Generate a hlist with necessary nodes for the bookmarks. To be inserted into a vlist that gets shipped out
function mkbookmarknodes(level,open_p,title)
    -- The bookmarks need three values, the level, the name and if it is
    -- open or closed
    setup_page()
    local openclosed
    if open_p then openclosed = 1 else openclosed = 2 end
    level = level or 1
    title = title or "no title for bookmark given"

    local n,counter = mkdest()
    local udw = node.new("whatsit","user_defined")
    udw.user_id = user_defined_bookmark
    udw.type = 115 -- a string
    udw.value = string.format("%d+%d+%d+%s",level,openclosed,counter,title)
    n.next = udw
    udw.prev = n
    local hlist = node.hpack(n)
    return hlist
end


-- For debugging in tables
function showtextatright(hbox,txt)
    hbox = node.vpack(hbox)
    local ff = fonts.lookup_fontfamily_name_number["__verysmall__"] or define_small_fontfamily()

    local x = mknodes(tostring(txt),ff)
    x = set_color_if_necessary(x,55)

    local texthbox = node.hpack(x)
    texthbox.depth = 0
    texthbox.height = 0

    local tail = node.tail(hbox)
    texthbox = node.insert_after(hbox,tail,texthbox)
    texthbox = node.hpack(texthbox)
    texthbox.width = hbox.width
    return texthbox
end

-- blue rule below the hbox for debugging purpose
function addhrule(hbox)
    local n = node.new("whatsit","pdf_literal")
    n.data = string.format("q 0.3 w [2 1] 0 d 0 0 1 RG 0 %g  m %g %g l S Q",  sp_to_bp(hbox.height),  -sp_to_bp(hbox.width) ,  sp_to_bp(hbox.height) )
    local tail = node.tail(hbox)
    hbox = node.insert_after(hbox,tail,n)
    hbox = node.hpack(hbox)
    return hbox
end

function boxit( box )
    local box = node.hpack(box)

    local rule_width = 0.1
    local wd = box.width                 / factor - rule_width
    local ht = (box.height + box.depth)  / factor - rule_width
    local dp = box.depth                 / factor - rule_width / 2

    local wbox = node.new("whatsit","pdf_literal")
    wbox.data = string.format("q 0.1 G %g w %g %g %g %g re s Q", rule_width, rule_width / 2, -dp, -wd, ht)
    wbox.mode = 0
    -- Draw box at the end so its contents gets "below" it.
    local tmp = node.tail(box.list)
    tmp.next = wbox
    return box
end

-- We have an array of color names to be used in attributes. Every color needs to get registered!
function register_color( name )
    if colors[name] ~= nil then
        return colors[name].index
    end
    colortable[#colortable + 1] = name
    return #colortable
end

function getrgb( colorvalue )
    local r,g,b
    local model = "rgb"
    if #colorvalue == 7 then
        r,g,b = string.match(colorvalue,"#?(%x%x)(%x%x)(%x%x)")
        r = math.round(tonumber(r,16) / 255, 3)
        g = math.round(tonumber(g,16) / 255, 3)
        b = math.round(tonumber(b,16) / 255, 3)
    elseif #colorvalue == 4 then
        r,g,b = string.match(colorvalue,"#?(%x)(%x)(%x)")
        r = math.round(tonumber(r,16) / 15, 3)
        g = math.round(tonumber(g,16) / 15, 3)
        b = math.round(tonumber(b,16) / 15, 3)
    end
    return r,g,b
end

-- color is an integer
function set_color_if_necessary( nodelist,color )
    local dontformat = node.has_attribute(nodelist,att_dont_format)

    if not color then return nodelist end

    local colorname
    if color == -1 then
        colorname = "black"
    else
        colorname = colortable[color]
    end

    local colstart = node.new("whatsit","pdf_colorstack")
    colstart.data  = colors[colorname].pdfstring
    if status.luatex_version < 79 then
        colstart.cmd = 1
    else
        colstart.command = 1
    end
    colstart.stack = 0
    if dontformat then
        node.set_attribute(colstart,att_dont_format,dontformat)
    end

    colstart.next = nodelist
    nodelist.prev = colstart

    local colstop  = node.new("whatsit","pdf_colorstack")
    colstop.data  = ""
    if status.luatex_version < 79 then
        colstop.cmd = 2
    else
        colstop.command = 2
    end
    colstop.stack = 0
    local last = node.tail(nodelist)
    last.next = colstop
    colstop.prev = last
    node.set_attribute(colstart,att_origin,origin_setcolorifnecessary)
    node.set_attribute(colstop,att_origin,origin_setcolorifnecessary)
    return colstart
end

function set_fontfamily_if_necessary(nodelist,fontfamily)
    -- if fontfamily == 0 then return end
    local fam
    while nodelist do
        if nodelist.id==vlist_node or nodelist.id==hlist_node  then
            set_fontfamily_if_necessary(nodelist.list,fontfamily)
        elseif nodelist.id == glue_node and nodelist.subtype == 100  then
              set_fontfamily_if_necessary(nodelist.leader,fontfamily)
        else
            fam = node.has_attribute(nodelist,att_fontfamily)
            if fam == 0 or ( fam == nil and nodelist.id == rule_node ) then
                node.set_attribute(nodelist,att_fontfamily,fontfamily)
            end
        end
        nodelist=nodelist.next
    end
end

function set_sub_supscript( nodelist,script )
    for glyf in node.traverse_id(glyph_node,nodelist) do
        node.set_attribute(glyf,att_script,script)
    end
end

function break_url( nodelist )
    local p

    local slash = string.byte("/")
    for n in node.traverse_id(glyph_node,nodelist) do
        p = node.new("penalty")

        if n.char == slash then
            p.penalty=-50
        else
            p.penalty=-5
        end
        p.next = n.next
        n.next = p
        p.prev = n
    end
    return nodelist
end

function colorbar( wd,ht,dp,color )
    local colorname = color
    if not colorname or colorname == "" then
        colorname = "black"
    end
    if not colors[colorname] then
        err("Color %q not found",color)
        colorname = "black"
    end

    local rule_start = node.new("whatsit","pdf_literal")
    rule_start.mode = 0
    rule_start.data = "q "..colors[colorname].pdfstring .. string.format(" 0 0 %g %g  re f Q ",sp_to_bp(wd),sp_to_bp(ht))

    local h = node.hpack(rule_start)
    h.width = wd
    h.depth = dp
    h.height = ht
    return h
end

local explode = function(s,p)
   local t = { }
   for s in string.gmatch(s,p) do
       if s ~= "" then
           t[#t+1] = s
       end
   end
   return t
end

function montage( nodelist_background,nodelist_foreground, origin_x, origin_y )
    local wd_bg = nodelist_background.width
    local ht_bg = nodelist_background.height + nodelist_background.depth
    local wd_fg = nodelist_foreground.width
    local ht_fg = nodelist_foreground.height + nodelist_foreground.depth
    local wd = wd_bg - wd_fg
    local ht = ht_bg - ht_fg
    origin_x = 100 - origin_x
    origin_y = 100 - origin_y
    local x = math.round(  sp_to_bp(wd - (wd * origin_x) / 100  ), 3 )
    local y = math.round(  sp_to_bp(ht - (ht * origin_y) / 100  ), 3 )

    local pdf_literal_q = node.new("whatsit","pdf_literal")
    pdf_literal_q.data = string.format("1 0 0 1 %g %g cm ",x, y)

    local pdf_literal_Q = node.new("whatsit","pdf_literal")
    pdf_literal_Q.data = string.format("1 0 0 1 %g 0 cm ",-1 * math.round(sp_to_bp(wd_bg),3))

    local pdf_save    = node.new("whatsit","pdf_save")
    local pdf_restore = node.new("whatsit","pdf_restore")
    local hbox

    hbox = node.insert_before(nodelist_background,nodelist_background, pdf_save)
    hbox = node.insert_after(hbox,node.tail(hbox),pdf_literal_Q)
    hbox = node.insert_after(hbox,node.tail(hbox),pdf_literal_q)
    hbox = node.insert_after(hbox,node.tail(hbox),nodelist_foreground)

    hbox = node.hpack(hbox)
    hbox.depth = 0
    hbox = node.insert_after(hbox,node.tail(hbox),pdf_restore)

    hbox = node.vpack(hbox)
    hbox.width = wd_bg
    hbox.height = ht_bg
    return hbox
end

--- Apply transformation matrix to object given at _nodelist_. Called from commmands#transformation.
function matrix( nodelist,matrix,origin_x,origin_y )
    local wd,ht = nodelist.width, nodelist.height + nodelist.depth
    local tbl = explode(matrix,"[^\t ]+")

    origin_x = 100 - origin_x
    origin_y = 100 - origin_y
    local x = math.round(  sp_to_bp(wd - (wd * origin_x) / 100  )  , 3 )
    local y = math.round(  sp_to_bp(ht - (ht * origin_y) / 100  )  , 3 )

    local pdf_literal_q = node.new("whatsit","pdf_literal")
    local pdf_literal_Q = node.new("whatsit","pdf_literal")

    pdf_literal_q.data   = string.format("q 1 0 0 1 %g -%g cm  q %g %g %g %g %g %g cm q 1 0 0 1 -%g %g cm ",x,y,tbl[1],tbl[2],tbl[3],tbl[4],tbl[5],tbl[6],x,y )
    pdf_literal_Q.data = "Q Q Q"

    local pdf_save    = node.new("whatsit","pdf_save")
    local pdf_restore = node.new("whatsit","pdf_restore")

    local hbox
    hbox = node.insert_before(nodelist,nodelist,pdf_literal_q)
    node.insert_after(nodelist,nodelist,pdf_literal_Q)
    hbox = node.insert_before(hbox,pdf_literal_q,pdf_save)
    hbox = node.hpack(hbox)

    hbox.depth = 0
    node.insert_after(hbox,node.tail(hbox),pdf_restore)

    local newbox = node.vpack(hbox)
    return newbox
end

--- Rotate an object clockwise with a given angle (in degrees).
---
--- First rotate the object at the top left corner (default)
--- If the origin is not top left, we need to shift the object
function rotate( nodelist,angle,origin_x,origin_y )
    local wd,ht = nodelist.width, nodelist.height + nodelist.depth
    nodelist.width = 0
    nodelist.height = 0
    nodelist.depth = 0

    -- positive would be counter clockwise, but CSS is clowckwise. So we multiply by -1
    local angle_rad = -1 * math.rad(angle)
    local sin = math.round(math.sin(angle_rad),3)
    local cos = math.round(math.cos(angle_rad),3)
    local q = node.new("whatsit","pdf_literal")
    q.mode = 0

    origin_x = 100 - origin_x
    origin_y = 100 - origin_y
    local x = math.round(  sp_to_bp(wd - (wd * origin_x) / 100  )  , 3 )
    local y = math.round(  sp_to_bp(ht - (ht * origin_y) / 100  )  , 3 )
    q.data = string.format("q 1 0 0 1 %g -%g cm  q %g %g %g %g 0 0 cm q 1 0 0 1 -%g %g cm ",x,y,cos,sin, -1 * sin,cos,x,y )
    q.next = nodelist
    local tail = node.tail(nodelist)
    local Q = node.new("whatsit","pdf_literal")
    Q.data = "Q Q Q"
    tail.next = Q
    local tmp = node.vpack(q)
    tmp.width  = 0
    tmp.height = 0
    tmp.depth = 0
    return tmp
end


--- Rotate a text on a given angle (`angle` on textblock).
function rotate_textblock( nodelist,angle )
    local wd,ht = nodelist.width, nodelist.height + nodelist.depth
    nodelist.width = 0
    nodelist.height = 0
    nodelist.depth = 0
    local angle_rad = math.rad(angle)
    local sin = math.round(math.sin(angle_rad),3)
    local cos = math.round(math.cos(angle_rad),3)
    local q = node.new("whatsit","pdf_literal")
    q.mode = 0
    local shift_x = math.round(math.min(0,math.sin(angle_rad) * sp_to_bp(ht)) + math.min(0,     math.cos(angle_rad) * sp_to_bp(wd)),3)
    local shift_y = math.round(math.max(0,math.sin(angle_rad) * sp_to_bp(wd)) + math.max(0,-1 * math.cos(angle_rad) * sp_to_bp(ht)),3)
    q.data = string.format("q %g %g %g %g %g %g cm",cos,sin, -1 * sin,cos, -1 * shift_x ,-1 * shift_y )
    q.next = nodelist
    local tail = node.tail(nodelist)
    local Q = node.new("whatsit","pdf_literal")
    Q.data = "Q"
    tail.next = Q
    local tmp = node.vpack(q)
    tmp.width  = math.abs(wd * cos) + math.abs(ht * math.cos(math.rad(90 - angle)))
    tmp.height = math.abs(ht * math.sin(math.rad(90 - angle))) + math.abs(wd * sin)
    tmp.depth = 0
    return tmp
end

--- Make a string XML safe
function xml_escape( str )
    if not str then return "" end
    local replace = {
        [">"] = "&gt;",
        ["<"] = "&lt;",
        ["\""] = "&quot;",
        ["&"] = "&amp;",
    }
    -- FIXME, str can be bool
    local ret = string.gsub(str,".",replace)
    return ret
end

--- See commands#save_dataset() for  documentation on the data structure for `xml_element`.
function xml_to_string( xml_element, level )
    level = level or 0
    local str = ""
    str = str .. string.rep(" ",level) .. "<" .. xml_element[".__local_name"]
    for k,v in pairs(xml_element) do
        if type(k) == "string" and not k:match("^%.") then
            str = str .. string.format(" %s=%q", k,xml_escape(v))
        end
    end
    str = str .. ">\n"
    for i,v in ipairs(xml_element) do
        str = str .. xml_to_string(v,level + 1)
    end
    str = str .. string.rep(" ",level) .. "</" .. xml_element[".__local_name"] .. ">\n"
    return str
end

--- Hyphenation and language handling
--- ---------------------------------

--- We map from symbolic names to (part of) file names. The hyphenation pattern files are
--- in the format `hyph-XXX.pat.txt` and we need to find out that `XXX` part.
language_mapping = {
    ["Czech"]                        = "cs",
    ["Danish"]                       = "da",
    ["Dutch"]                        = "nl",
    ["English (Great Britan)"]       = "en_GB",
    ["English (USA)"]                = "en_US",
    ["Finnish"]                      = "fi",
    ["French"]                       = "fr",
    ["German"]                       = "de",
    ["Greek"]                        = "el",
    ["Ancient Greek"]                = "grc",
    ["Hungarian"]                    = "hu",
    ["Italian"]                      = "it",
    ["Norwegian Bokmål"]             = "nb",
    ["Norwegian Nynorsk"]            = "nn",
    ["Polish"]                       = "pt",
    ["Portuguese"]                   = "pt",
    ["Russian"]                      = "ru",
    ["Serbian"]                      = "sr",
    ["Spanish"]                      = "es",
    ["Swedish"]                      = "sv",
    ["Turkish"]                      = "tr",
}

--- Supported language names. Not all are currently available from the publisher
---
---     af, Afrikaans - Afrikaans
---     as, Assamese - Assamesisch
---     bg, Bulgarian - Bulgarisch
---     ca, Catalan - Katalanisch
---     cs, Czech - Tschechisch
---     cy, Welsh - Kymrisch
---     da, Danish - Dänisch
---     de, German - Deutsch
---     el, Greek - Neugriechisch
---     en, English - Englisch
---     eo, Esperanto - Esperanto
---     es, Spanish - Spanisch
---     et, Estonian - Estnisch
---     eu, Basque - Baskisch
---     fi, Finnish - Finnisch
---     fr, French - Französisch
---     ga, Irish - Irisch
---     gl, Galician - Galicisch
---     grc, Ancient Greek - Altgriechisch
---     gu, Gujarati - Gujarati
---     hi, Hindi - Hindi
---     hr, Croatian - Kroatisch
---     hu, Hungarian - Ungarisch
---     hy, Armenian - Armenisch
---     ia, Interlingua - Interlingua
---     id, Indonesian - Bahasa Melayu
---     is, Icelandic - Isländisch
---     it, Italian - Italienisch
---     ku, Kurdish - Kurdisch
---     kn, Kannada - Kannada
---     la, Latin - Latein
---     lo, Lao - Laotisch
---     lt, Lithuanian - Litauisch
---     ml, Malayalam - Malayalam
---     lv, Latvian - Lettisch
---     ml, Malayalam - Malayalam
---     mn, Mongolian - Mongolisch
---     mr, Marathi - Marathi
---     nb, Norwegian Bokmål - Bokmål
---     nl, Dutch - Niederländisch
---     nn, Norwegian Nynorsk - Nynorsk
---     or, Oriya - Oriya
---     pa, Panjabi - Pandschabi
---     pl, Polish - Polnisch
---     pt, Portuguese - Portugiesisch
---     ro, Romanian - Rumänisch
---     ru, Russian - Russisch
---     sa, Sanskrit - Sanskrit
---     sk, Slovak - Slowakisch
---     sl, Slovenian - Slowenisch
---     sr, Serbian - Serbisch
---     sv, Swedish - Schwedisch
---     ta, Tamil - Tamil
---     te, Telugu - Telugu
---     tk, Turkmen - Turkmenisch
---     tr, Turkish - Türkisch
---     uk, Ukrainian - Ukrainisch
---     zh, Chinese - Chinesisch


language_filename = {
    ["af"]    = "af",
    ["as"]    = "as",
    ["bg"]    = "bg",
    ["ca"]    = "ca",
    ["cs"]    = "cs",
    ["cy"]    = "cy",
    ["da"]    = "da",
    ["de"]    = "de-1996",
    ["el"]    = "el-monoton",
    ["en"]    = "en-gb",
    ["en_GB"] = "en-gb",
    ["en_US"] = "en-us",
    ["eo"]    = "eo",
    ["es"]    = "es",
    ["et"]    = "et",
    ["eu"]    = "eu",
    ["fi"]    = "fi",
    ["fr"]    = "fr",
    ["ga"]    = "ga",
    ["gl"]    = "gl",
    ["grc"]   = "grc",
    ["gu"]    = "gu",
    ["hi"]    = "hi",
    ["hr"]    = "hr",
    ["hu"]    = "hu",
    ["hy"]    = "hy",
    ["ia"]    = "ia",
    ["id"]    = "id",
    ["is"]    = "is",
    ["it"]    = "it",
    ["ku"]    = "kmr",
    ["kn"]    = "kn",
    ["la"]    = "la",
    ["lo"]    = "lo",
    ["lt"]    = "lt",
    ["ml"]    = "ml",
    ["lv"]    = "lv",
    ["ml"]    = "ml",
    ["mn"]    = "mn-cyrl",
    ["mr"]    = "mr",
    ["nb"]    = "nb",
    ["nl"]    = "nl",
    ["nn"]    = "nn",
    ["or"]    = "or",
    ["pa"]    = "pa",
    ["pl"]    = "pl",
    ["pt"]    = "pt",
    ["ro"]    = "ro",
    ["ru"]    = "ru",
    ["sa"]    = "sa",
    ["sk"]    = "sk",
    ["sl"]    = "sl",
    ["sr"]    = "sr",
    ["sv"]    = "sv",
    ["ta"]    = "ta",
    ["te"]    = "te",
    ["tk"]    = "tk",
    ["tr"]    = "tr",
    ["uk"]    = "uk",
    ["zh"]    = "zh-latn",
}

--- Once a hyphenation pattern file is loaded, we only need the _id_ of it. This is stored in the
--- `languages` table. Key is the filename part (such as `de-1996`) and the value is the internal
--- language id.
languages = {}
languages_id_lang = {}

--- Return a lang object
function get_language(id_or_locale_or_name)
    local num = tonumber(id_or_locale_or_name)
    if num then
        return languages_id_lang[num]
    end
    local locale = id_or_locale_or_name

    if language_mapping[id_or_locale_or_name] then
        locale = language_mapping[id_or_locale_or_name]
    end
    if languages[locale] then
        return languages[locale]
    end

    local filename_part
    if language_filename[locale] then
        filename_part = language_filename[locale]
    else
        local lang, _ = unpack(string.explode(locale,"_"))
        if language_filename[lang] then
            filename_part = language_filename[lang]
        end
    end
    if not filename_part then
        err("Can't find hyphenation patterns for language %s",tostring(locale))
        return 0
    end

    local filename = string.format("hyph-%s.pat.txt",filename_part)
    log("Loading hyphenation patterns %q.",filename)
    local path = kpse.find_file(filename)
    local pattern_file = io.open(path)
    local pattern = pattern_file:read("*all")
    pattern_file:close()

    local l = lang.new()
    l:patterns(pattern)
    local id = l:id()
    log("Language id: %d",id)
    local ret = { id = id, l = l }
    languages_id_lang[id] = ret
    languages[locale] = ret
    return ret
end

--- The language name is something like `German` or a locale.
function get_languagecode( locale_or_name )
    local tmp = get_language(locale_or_name)
    return tmp.id
end

function set_mainlanguage( mainlanguage )
    log("Setting default language to %q",mainlanguage or "?")
    defaultlanguage = get_languagecode(mainlanguage)
end


--- Return the language numbers used in this nodelist. Used before `do_linebreak()` to change pre-hyphenchar temporarily.
function get_languages_used( nodelist )
    local langs = {}
    for n in node.traverse_id(glyph_node,nodelist) do
        langs[n.lang] = true
    end
    local ret = {}
    for k,_ in pairs(langs) do
        ret[#ret + 1] = k
    end
    return ret
end


--- Misc
--- --------
function set_pageformat( wd,ht )
    options.pagewidth    = wd
    options.pageheight  = ht
    tex.pdfpagewidth =  wd
    tex.pdfpageheight = ht
    -- why the + 2cm? is this for the trim-/art-/bleedbox? FIXME: document
    tex.pdfpagewidth  = tex.pdfpagewidth   + tex.sp("2cm")
    tex.pdfpageheight = tex.pdfpageheight  + tex.sp("2cm")

    -- necessary? FIXME: check if necessary.
    tex.hsize = wd
    tex.vsize = ht
end

-- Return remaining height (sp), first row, last row
function get_remaining_height(area,allocate)
    local cols = current_grid:number_of_columns(area)
    local startcol = 1
    local row,firstrow,lastrow,maxrows
    firstrow = current_grid:current_row(area)
    if not firstrow then
        err("get remaining height: no current row")
        firstrow = 1
    end
    maxrows  = current_grid:number_of_rows(area)
    if allocate == "auto" then
        while firstrow <= maxrows and (not current_grid:row_has_some_space(firstrow,area)) do
            firstrow = firstrow + 1
        end

        local row = firstrow + 1
        while row <= maxrows and current_grid:row_has_some_space(row,area) do
            row = row + 1
        end

        if row > maxrows then
            return ( row - firstrow ) * current_grid.gridheight, firstrow
        end
        local lastrow = row
        while not current_grid:fits_in_row_area(startcol,cols,lastrow,area) and lastrow <= maxrows do

            lastrow = lastrow + 1
        end
        lastrow = lastrow - 1
        if lastrow == firstrow then lastrow = nil end
        if lastrow >= maxrows then lastrow = nil end
        return (row - firstrow) * current_grid.gridheight, firstrow,lastrow
    end
    if not current_grid:fits_in_row_area(startcol,cols,firstrow,area) then
        while firstrow <= maxrows do
            if current_grid:fits_in_row_area(startcol,cols,firstrow,area) then
                break
            end
            firstrow = firstrow + 1
        end
    end

    row = firstrow

    while current_grid:fits_in_row_area(startcol,cols,row,area) and row <= maxrows do
        row = row + 1
    end

    lastrow = row

    while row <= maxrows do
        if current_grid:fits_in_row_area(startcol,cols,row,area) then
            return ( lastrow - firstrow)  * current_grid.gridheight, firstrow, firstrow
        end
        row = row + 1
    end
    return ( lastrow - firstrow)  * current_grid.gridheight, firstrow, nil

end

function next_row(rownumber,areaname,rows)
    local grid = current_grid

    if rownumber then
        grid:set_current_row(rownumber,areaname)
        return
    end

    local current_row
    current_row = grid:find_suitable_row(1,grid:number_of_columns(areaname),rows,areaname)
    if not current_row then
        next_area(areaname)
        setup_page()
        grid = current_page.grid
        grid:set_current_row(1)
    else
        grid:set_current_row(current_row + rows - 1,areaname)
        grid:set_current_column(1,areaname)
    end
end

function empty_block()
    local r = node.new("hlist")
    r.width = 0
    r.height = 0
    r.depth = 0
    local v = node.vpack(r)
    trace("empty_block")
    return v
end


function emergency_block()
    local r = node.new("rule")
    r.width = 5 * 2^16
    r.height = 5 * 2^16
    r.depth = 0
    local v = node.vpack(r)
    trace("emergency_block")
    return v
end



--- Defaults
--- --------

--- This function is only called once from `dothings()` during startup phase. We define
--- a family with regular, bold, italic and bolditalic font with size 10pt (we always
--- measure font size in dtp points)
function define_default_fontfamily()
    local fam={
        size         = 10 * factor,
        baselineskip = 12 * factor,
        scriptsize   = 10 * factor * 0.8,
        scriptshift  = 10 * factor * 0.3,
        name = "text"
    }
    local ok,tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Regular",fam.size)
    fam.normal = tmp
    fam.fontfaceregular = "TeXGyreHeros-Regular"
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Regular",fam.scriptsize)
    fam.normalscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Bold",fam.size)
    fam.bold = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Bold",fam.scriptsize)
    fam.boldscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Italic",fam.size)
    fam.italic = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Italic",fam.scriptsize)
    fam.italicscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-BoldItalic",fam.size)
    fam.bolditalic = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-BoldItalic",fam.scriptsize)
    fam.bolditalicscript = tmp
    fonts.lookup_fontfamily_number_instance[#fonts.lookup_fontfamily_number_instance + 1] = fam
    fonts.lookup_fontfamily_name_number["text"]=#fonts.lookup_fontfamily_number_instance
end

function define_small_fontfamily()
    local fam={
        size         = 4 * factor,
        baselineskip = 4 * factor,
        scriptsize   = 4 * factor * 0.8,
        scriptshift  = 4 * factor * 0.3,
        name = "__verysmall__"
    }
    local ok,tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Regular",fam.size)
    fam.normal = tmp
    fam.fontfaceregular = "TeXGyreHeros-Regular"
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Regular",fam.scriptsize)
    fam.normalscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Bold",fam.size)
    fam.bold = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Bold",fam.scriptsize)
    fam.boldscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Italic",fam.size)
    fam.italic = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-Italic",fam.scriptsize)
    fam.italicscript = tmp

    ok,tmp = fonts.make_font_instance("TeXGyreHeros-BoldItalic",fam.size)
    fam.bolditalic = tmp
    ok,tmp = fonts.make_font_instance("TeXGyreHeros-BoldItalic",fam.scriptsize)
    fam.bolditalicscript = tmp
    fonts.lookup_fontfamily_number_instance[#fonts.lookup_fontfamily_number_instance + 1] = fam
    fonts.lookup_fontfamily_name_number["__verysmall__"]=#fonts.lookup_fontfamily_number_instance
    return fonts.lookup_fontfamily_name_number["__verysmall__"]
end


-- deepcopy is for <Copy-of>
function deepcopy(t)
    local typ = type(t)
    if typ ~= 'table' then return t end
    local mt = getmetatable(t)
    local res = {}
    for k,v in pairs(t) do
        typ = type(v)
        if typ == 'table' then
            v = deepcopy(v)
        else
            if node.is_node(v) then
                v = node.copy_list(v)
            end
        end
        res[k] = v
    end
    setmetatable(res,mt)
    return res
end

-- Return the height of the page given by the relative pagenumber
-- (starting from the current_pagenumber).
-- This is used in tables to get the hight of a page in a multi
-- page table
function getheight( relative_pagenumber )
    local thispagenumber = current_pagenumber + relative_pagenumber - 1
    -- w("getheight for page number %d which is page number %d in the PDF",relative_pagenumber,thispagenumber)
    local thispage = pages[thispagenumber]
    local areaname = xpath.get_variable("__currentarea")
    if thispage then
        local firstrow = thispage.grid:first_free_row(areaname)
        local space = thispage.grid:remaining_height_sp(firstrow,areaname)
        return space
    end
end


--- Image handling
--- --------------

function set_image_length(len,width_or_height)
    if len == nil or len == "auto" then
        return nil
    elseif len == "100%" and width_or_height == "width" then
        return xpath.get_variable("__maxwidth")
    elseif tonumber(len) then
        if width_or_height == "width" then
            return current_grid:width_sp(len)
        else
            return len * current_grid.gridheight
        end
    else
        return tex.sp(len)
    end
end


function calculate_image_width_height( image, width,height,minwidth,minheight,maxwidth, maxheight )
    -- from http://www.w3.org/TR/CSS2/visudet.html#min-max-widths:
    --
    -- Constraint Violation                                                           Resolved Width                      Resolved Height
    -- ===================================================================================================================================================
    --  1 none                                                                        w                                   h
    --  2 w > max-width                                                               max-width                           max(max-width * h/w, min-height)
    --  3 w < min-width                                                               min-width                           min(min-width * h/w, max-height)
    --  4 h > max-height                                                              max(max-height * w/h, min-width)    max-height
    --  5 h < min-height                                                              min(min-height * w/h, max-width)    min-height
    --  6 (w > max-width) and (h > max-height), where (max-width/w ≤ max-height/h)    max-width                           max(min-height, max-width * h/w)
    --  7 (w > max-width) and (h > max-height), where (max-width/w > max-height/h)    max(min-width, max-height * w/h)    max-height
    --  8 (w < min-width) and (h < min-height), where (min-width/w ≤ min-height/h)    min(max-width, min-height * w/h)    min-height
    --  9 (w < min-width) and (h < min-height), where (min-width/w > min-height/h)    min-width                           min(max-height, min-width * h/w)
    -- 10 (w < min-width) and (h > max-height)                                        min-width                           max-height
    -- 11 (w > max-width) and (h < min-height)                                        max-width                           min-height

    if width < minwidth and height > maxheight then
        -- w("10")
        width = minwidth
        height = maxheight
    elseif width > maxwidth and height < minheight then
        -- w("11")
        width = maxwidth
        height = minheight
    elseif width > maxwidth and height > maxheight and maxwidth / width <= maxheight / height then
        -- w("6")
        width = maxwidth
        height = math.max(minheight, maxwidth * height/width)
    elseif width > maxwidth and height > maxheight and maxwidth / width > maxheight / height then
        -- w("7")
        width = math.max(minwidth,maxheight * width / height)
        height = maxheight
    elseif width < minwidth and height < minheight and minwidth / width <= minheight / height then
        -- w("8")
        width  = math.min(maxwidth,minheight * width / height)
        height = minheight
    elseif width < minwidth and height < minheight and minwidth / width > minheight / height then
        -- w("9")
        width = minwidth
        height = math.min(maxheight,minwidth * height / width)
    elseif width > maxwidth then
        -- w("2")
        width = maxwidth
        height = math.max(maxwidth * height / width, minheight )
    elseif width < minwidth then
        -- w("3")
        width = minwidth
        height = math.min(minwidth * height / width, maxheight)
    elseif height > maxheight then
        -- w("4")
        width = math.max(maxheight * width / height, minwidth)
        height = maxheight
    elseif height < minheight then
        -- w("5")
        width = math.min(minheight * width / height, maxwidth)
        height = minheight
    end

    -- If one of height or width is given, the other one should
    -- be adjusted to keep the aspect ratio
    if height == image.height then
        if width ~= image.width then
            height = height * width / image.width
        end
    elseif width == image.width then
        if height ~= image.height then
            width = width *  height / image.height
        end
    end
    return width, height
end


local images = {}
function new_image( filename, page, box,fallback)
    return imageinfo(filename,page,box,fallback)
end

-- Retrieve image from an URL if its not cached
function get_image(requeste_url,fallback)
    local imgcache = os.getenv("IMGCACHE")
    local parsed_url = url.parse(requeste_url)
    -- http://placekitten.com/g/200/300?foo=bar gives
    -- x = {
    --  ["path"] = "/g/200/300"
    --  ["scheme"] = "http"
    --  ["query"] = "foo=bar"
    --  ["authority"] = "placekitten.com"
    --  ["host"] = "placekitten.com"
    -- },
    if parsed_url.scheme == nil or parsed_url.scheme == "file" then
        if type(parsed_url.path) == "string" then
            -- let's assume its a file
            return imageinfo("file:" .. parsed_url.path)
        end
    end
    local request_filename = parsed_url.host .. parsed_url.path
    if parsed_url.query then
        request_filename = request_filename .. "?" .. parsed_url.query
    end
    -- md5 should be over the complete part after the host
    local mdfivesum = string.gsub(md5.sum(request_filename),".",function(chr) return string.format("%02x",string.byte(chr)) end)
    local path_to_image = os.getenv("IMGCACHE") .. os_separator .. mdfivesum

    if lfs.isfile(path_to_image) then
        log("Image: string used for caching (-> md5): %q",request_filename)
        log("Read image file from cache: %s",path_to_image)
        return imageinfo(path_to_image)
    end

    -- c = {
    --   ["last-modified"] = "Mon, 21 Oct 2013 12:45:54 GMT"
    --   ["connection"] = "close"
    --   ["accept-ranges"] = "bytes"
    --   ["date"] = "Thu, 13 Feb 2014 16:29:11 GMT"
    --   ["content-length"] = "52484"
    --   ["content-type"] = "image/jpeg"
    -- }
    log("Retrieving file: %q",tostring(requeste_url))
    txt, statuscode, c = http.request(requeste_url)
    if statuscode ~= 200 then
        err("404 when retrieving image %q",requeste_url)
        return imageinfo(nil,nil,nil,fallback) -- nil is "filenotfound.pdf"
    end
    if #txt == 0 then
        err("Empty image in href request")
        return imageinfo(nil,nil,nil,fallback)
    end
    -- Create the temporary directory if necessary
    if not lfs.isdir(imgcache) then
        local imgcachepaths = string.explode(imgcache,os_separator)
        local tmp = ""
        for i=2, #imgcachepaths do
            tmp = tmp .. os_separator .. imgcachepaths[i]
            if not lfs.isdir(tmp) then
                local ok,e = lfs.mkdir(tmp)
                if not ok then
                    err("Could not create temporary directory for images: %q",tmp)
                end
            end
        end
    end

    local file,e = io.open(path_to_image,"wb")
    if file == nil then
        err("Could not open image file for writing into temp directory: %q",e)
        return imageinfo(nil,nil,nil,fallback)
    end
    local ok
    ok, e = file:write(txt)
    if not ok then
        err("Could not write image file into temp directory %q",e)
        return imageinfo(nil,nil,nil,fallback)
    end
    file:flush()
    file:close()

    -- Just re-run this function. The image is now cached
    return get_image(requeste_url,fallback)
end

function get_fallback_image_name( filename, missingfilename )
    if filename then
        warning("Using fallback %q, missing file name is %q", filename, missingfilename)
        return filename
    else
        return "filenotfound.pdf"
    end
end

-- Box is none, media, crop, bleed, trim, art
function imageinfo( filename,page,box,fallback )
    page = page or 1
    box = box or "crop"
    -- there is no filename, we should fail or throw an error
    if not filename then
        err("No filename given for image")
        filename = get_fallback_image_name(fallback)
    end
    if type(filename) ~= "string" then
        err("something is wrong with the filename for the image, not a string")
        filename = get_fallback_image_name(fallback)
    end

    local new_name = filename .. tostring(page) .. tostring(box)

    if images[new_name] then
        return images[new_name]
    end

    if not find_file_location(filename) then
        if options.imagenotfounderror then
            err("Image %q not found!",filename or "???")
        else
            warning("Image %q not found!",filename or "???")
        end
        filename = get_fallback_image_name(fallback,filename)
        page = 1
    end
    -- example is wrong: one based index
    -- <?xml version="1.0" ?>
    -- <imageinfo>
    --    <cells_x>30</cells_x>
    --    <cells_y>21</cells_y>
    --    <segment x1='13' y1='0' x2='16' y2='0' />
    --    <segment x1='13' y1='1' x2='16' y2='1' />
    --    <segment x1='11' y1='2' x2='18' y2='2' />
    --    <segment x1='10' y1='3' x2='18' y2='3' />
    --    <segment x1='10' y1='4' x2='18' y2='4' />
    --    <segment x1='9' y1='5' x2='20' y2='5' />
    --    <segment x1='8' y1='6' x2='20' y2='6' />
    --    <segment x1='8' y1='7' x2='20' y2='7' />
    --    <segment x1='7' y1='8' x2='21' y2='8' />
    --    <segment x1='6' y1='9' x2='21' y2='9' />
    --    <segment x1='5' y1='10' x2='24' y2='10' />
    --    <segment x1='5' y1='11' x2='24' y2='11' />
    --    <segment x1='4' y1='12' x2='25' y2='12' />
    --    <segment x1='3' y1='13' x2='25' y2='13' />
    --    <segment x1='3' y1='14' x2='27' y2='14' />
    --    <segment x1='2' y1='15' x2='27' y2='15' />
    --    <segment x1='1' y1='16' x2='28' y2='16' />
    --  </imageinfo>
    local xmlfilename = string.gsub(filename,"(%..*)$","") .. ".xml"

    local mt
    if kpse.filelist[xmlfilename] then
        local xmltab,msg = load_xml(xmlfilename,"Imageinfo")
        if not xmltab then
            err(msg)
        else
            mt = {}
            local segments = {}
            local cells_x,cells_y
            for _,v in ipairs(xmltab) do
                if v[".__local_name"] == "cells_x" then
                    cells_x = v[1]
                elseif v[".__local_name"] == "cells_y" then
                    cells_y = v[1]
                elseif v[".__local_name"] == "segment" then
                    -- 0 based segments
                    segments[#segments + 1] = {v.x1,v.y1,v.x2,v.y2}
                end
            end
            -- we have parsed the file, let's build a beautiful 2dim array
            mt.max_x = cells_x
            mt.max_y = cells_y
            for i=1,cells_y do
                mt[i] = {}
                for j=1,cells_x do
                    mt[i][j] = 0
                end
            end
            for i,v in ipairs(segments) do
                for x=v[1],v[3] do
                    for y=v[2],v[4] do
                        mt[y][x] = 1
                    end
                end
            end
        end
    end

    if not images[new_name] then
        local image_info = img.scan{filename = filename, pagebox = box, page=page }
        images[new_name] = { img = image_info, allocate = mt }
    end
    return images[new_name]
end

--- Sorting
--- -------
--- The sorting code is currently used for index generation (commands#makeindex)

-- see http://lua.2524044.n2.nabble.com/A-stable-sort-td7648892.html
-- public domain or cc0

-- If you're using LuaJIT, change to 72.
local max_chunk_size = 12

function insertion_sort( array, first, last, goes_before )
  for i = first + 1, last do
    local k = first
    local v = array[i]
    for j = i, first + 1, -1 do
      if goes_before( v, array[j-1] ) then
        array[j] = array[j-1]
      else
        k = j
        break
      end
    end
    array[k] = v
  end
end

function merge( array, workspace, low, middle, high, goes_before )
  local i, j, k
  i = 1
  -- Copy first half of array to auxiliary array
  for j = low, middle do
    workspace[ i ] = array[ j ]
    i = i + 1
  end
  i = 1
  j = middle + 1
  k = low
  while true do
    if (k >= j) or (j > high) then
      break
    end
    if goes_before( array[ j ], workspace[ i ] )  then
      array[ k ] = array[ j ]
      j = j + 1
    else
      array[ k ] = workspace[ i ]
      i = i + 1
    end
    k = k + 1
  end
  -- Copy back any remaining elements of first half
  for k = k, j-1 do
    array[ k ] = workspace[ i ]
    i = i + 1
  end
end


function merge_sort( array, workspace, low, high, goes_before )
  if high - low < max_chunk_size then
    insertion_sort( array, low, high, goes_before )
  else
    local middle = math.floor((low + high)/2)
    merge_sort( array, workspace, low, middle, goes_before )
    merge_sort( array, workspace, middle + 1, high, goes_before )
    merge( array, workspace, low, middle, high, goes_before )
  end
end

function stable_sort( array, goes_before )
    local n = #array
    if n < 2 then return array end
    goes_before = goes_before or function (a, b)  return a < b  end
    local workspace = {}
    --  Allocate some room.
    workspace[ math.floor( (n+1)/2 ) ] = array[1]
    if goes_before(array[1],array[1]) then
        error"invalid order function for sorting"
    end
    merge_sort( array, workspace, 1, n, goes_before )
    return array
end
-- end of stable sorting function


--- Garbage Collection
--- -------------------
--- This is somewhat experimental. The idea is to remove all nodes from the
--- contents of the old value of that variable. Hopefully this has no
--- evil side effects. We'll find out....
function flush_table(tbl)
    for k,v in pairs(tbl) do
        if k == ".__context" or k == ".__parent" then
            -- nothing, to prevent infinite loops
        elseif type(v) == "table" then
            flush_table(v)
        elseif type(v) == "userdata" then
            node.flush_list(v)
        else
            k = nil
        end
    end
end

function flush_variable( varname )
    local x = xpath.get_variable(varname)
    if type(x) == "table" then
        flush_table(x)
    end
end


file_end("publisher.lua")

