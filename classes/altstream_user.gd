class_name AltStreamUser
extends RefCounted

var username     : String
var display_name : String # "author" in the API
var pronouns     : String
var roles        : Dictionary[AltStreamService.Role, bool]
var badges       : Array[AltStreamService.Role]
var avatar_url   : String
var user_color   : Color
