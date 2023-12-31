module Models.OrganizationId exposing (OrganizationId, decode, encode, one, zero)

import Json.Decode as Decode
import Json.Encode exposing (Value)
import Libs.Models.Uuid as Uuid exposing (Uuid)


type alias OrganizationId =
    Uuid


zero : OrganizationId
zero =
    Uuid.zero


one : OrganizationId
one =
    Uuid.one


encode : OrganizationId -> Value
encode value =
    Uuid.encode value


decode : Decode.Decoder OrganizationId
decode =
    Uuid.decode
