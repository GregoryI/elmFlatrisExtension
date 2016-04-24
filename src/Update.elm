module Update (update) where
import Model exposing (..)
import Actions exposing (..)
import Effects exposing (Effects)
import Tetriminos
import Time exposing (Time)
import Grid
import Random
import LocalStorage
import Task exposing (Task)


getFromStorage : String -> Effects Action
getFromStorage key =
  LocalStorage.get key `Task.onError` (\_ -> Task.succeed Nothing)
    |> Task.map (\result -> Load (Maybe.withDefault "" result))
    |> Effects.task


saveToStorage : String -> String -> Effects Action
saveToStorage key value =
  LocalStorage.set key value
    |> Task.toMaybe
    |> Task.map (always Saved)
    |> Effects.task


update : Action -> Model -> (Model, Effects Action)
update action model =
  case action of
    Init time ->
      let
        (next, seed) = Tetriminos.random (Random.initialSeed (floor time))
      in
        ( spawnTetrimino {model | seed = seed, next = next}
        , getFromStorage "elm-flatris"
        )
    Load string ->
      (Model.decode string model, Effects.tick Tick)
    Start ->
      ( { model
        | state = Playing
        , lines = 0
        , score = 0
        , grid = Grid.empty
        }
      , Effects.none
      )
    Pause ->
      ( {model | state = Paused}
      , Effects.none
      )
    Resume ->
      ( {model | state = Playing}
      , Effects.none
      )
    Move 0 ->
      ( {model | direction = Nothing}
      , Effects.none
      )
    Move direction ->
      ( { model
        | direction = Just { active = True
                           , direction = direction
                           , elapsed = 0
                           }
        }
      , Effects.none
      )
    Rotate False ->
      ( {model | rotation = Nothing}
      , Effects.none
      )
    Rotate True ->
      ( {model | rotation = Just {active = True, elapsed = 0}}
      , Effects.none
      )
    Accelerate on ->
      ( {model | acceleration = on}
      , Effects.none
      )
    UnlockButtons ->
      ( {model | rotation = Nothing, direction = Nothing, acceleration = False, space = False}
      , Effects.none
      )
    Tick time ->
      let
        model =
          if model.state == Playing then
            animate time model
          else
            {model | animation = Nothing}
      in
        (model, saveToStorage "elm-flatris" (Model.encode 0 model))
    Saved ->
      (model, Effects.tick Tick)
    DropSpacebar pressed -> 
      ( {model | space = pressed}
      , Effects.none
      )



animate : Time -> Model -> Model
animate time model =
  let
    elapsed = case model.animation of
      Nothing -> 0
      Just {prevClockTime} -> min (time - prevClockTime) 25
    animation = Just {prevClockTime = time, elapsed = elapsed}
  in
    {model | animation = animation}
    |> moveTetrimino elapsed
    |> rotateTetrimino elapsed
    |> dropTetrimino elapsed
    |> spaceDrop
    |> checkEndGame


spawnTetrimino : Model -> Model
spawnTetrimino model =
  let
    (next, seed) = Tetriminos.random model.seed
    (x, y) = Grid.initPosition model.width model.next
  in
    { model
    | next = next
    , seed = seed
    , active = model.next
    , position = (x, toFloat y)
    }


moveTetrimino : Time -> Model -> Model
moveTetrimino elapsed model =
  case model.direction of
    Just state ->
      {model | direction = Just (activateButton 150 elapsed state)}
      |> (if state.active then moveTetrimino' state.direction else identity)
    Nothing -> model


moveTetrimino' : Int -> Model -> Model
moveTetrimino' dx model =
  let
    (x, y) = model.position
    x' = x + dx
  in
    if Grid.collide model.width model.height x' (floor y) model.active model.grid then
      model
    else
      {model | position = (x', y)}


activateButton : Time -> Time -> {a | active: Bool, elapsed: Time} -> {a | active: Bool, elapsed: Time}
activateButton interval elapsed state =
  let
    elapsed' = state.elapsed + elapsed
  in
    if elapsed' > interval then
      {state | active = True, elapsed = elapsed' - interval}
    else
      {state | active = False, elapsed = elapsed'}


rotateTetrimino : Time -> Model -> Model
rotateTetrimino elapsed model =
  case model.rotation of
    Just rotation ->
      {model | rotation = Just (activateButton 300 elapsed rotation)}
      |> (if rotation.active then rotateTetrimino' else identity)
    Nothing -> model


rotateTetrimino' : Model -> Model
rotateTetrimino' model =
  let
    (x, y) = model.position
    rotated = Grid.rotate True model.active
    shiftPosition deltas =
      case deltas of
        dx :: remainingDeltas ->
          if Grid.collide model.width model.height (x + dx) (floor y) rotated model.grid then
            shiftPosition remainingDeltas
          else
            { model
            | active = rotated
            , position = (x + dx, y)
            }
        [] ->
          model
  in
    shiftPosition [0, 1, -1, 2, -2]


checkEndGame : Model -> Model
checkEndGame model =
  if List.any identity (Grid.mapToList (\_ (_, y) -> y < 0) model.grid) then
    {model | state = Stopped}
  else
    model


dropTetrimino : Time -> Model -> Model
dropTetrimino elapsed model =
  let
    (x, y) = model.position
    speed =
      if model.acceleration then
        25
      else
        max 25 (800 - 25 * toFloat (level model - 1))
    y' = y + elapsed / speed
  in
    if Grid.collide model.width model.height x (floor y') model.active model.grid then
      let
        score = List.length (Grid.mapToList (\_ _ _ -> True) model.active)
      in
        { model
        | grid = Grid.stamp x (floor y) model.active model.grid
        , score = model.score + score * (if model.acceleration then 2 else 1)
        }
        |> spawnTetrimino
        |> clearLines
    else
      {model | position = (x, y')}

spaceDrop : Model -> Model
spaceDrop model = 
  let
    (x, y) = model.position
  in
    if model.space then
      spaceDrop' model x y
    else model

spaceDrop' : Model -> Int -> Float -> Model
spaceDrop' model x y =
  if Grid.collide model.width model.height x (floor y) model.active model.grid then
    {model | position = (x, y-1), space = False}
  else spaceDrop' model x (y +1)


clearLines : Model -> Model
clearLines model =
  let
    (grid, lines) = Grid.clearLines model.width model.grid
    bonus = case lines of
      0 -> 0
      1 -> 100
      2 -> 300
      3 -> 500
      _ -> 800
  in
    { model
    | grid = grid
    , score = model.score + bonus * level model
    , lines = model.lines + lines
    }


level : Model -> Int
level model =
  model.lines // 10 + 1
