class_name AltstreamUser
extends RefCounted

var username     : String
var display_name : String # "author" in the API
var pronouns     : String
var roles        : Dictionary[AltstreamService.Role, bool]
var badges       : Array[AltstreamService.Role]
var avatar_url   : String
var user_color   : Color
