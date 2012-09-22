-- slitherlink.hs 
-- a solver for Slitherlink puzzles
-- Copyright (C) 2012 by Harald Bögeholz
-- See LICENSE file for license information

import Data.Array.IArray
import Control.Monad
import Control.Monad.Instances()
import Data.List (find)
import System.Environment
import qualified Data.Set as Set

data Constraint = Unconstrained | Exactly Int deriving (Eq)
instance Show Constraint where
    show Unconstrained = "."
    show (Exactly x) = show x

readConstraint :: Char -> Either String Constraint
readConstraint '.' = Right Unconstrained
readConstraint '0' = Right $ Exactly 0
readConstraint '1' = Right $ Exactly 1
readConstraint '2' = Right $ Exactly 2
readConstraint '3' = Right $ Exactly 3
readConstraint c = Left $ "Invalid character " ++ show c ++ "."

type ProblemList = [[Constraint]]

readProblemList ::  String -> Either String ProblemList
readProblemList = (mapM . mapM) readConstraint . lines

type Problem = Array (Int, Int) Constraint

readProblem :: String -> Either String Problem
readProblem s = do
            pl <- readProblemList s
            when (null pl) $ Left "Problem is empty."
            let columns = length $ head pl
            when (columns == 0) $ Left "Problem starts with an empty line."
            unless (all ((== columns) . length) pl) $ Left "Problem not rectangular."
            let rows = length pl
            return $ listArray ((0, 0), (rows-1, columns-1)) $ concat pl 

data SixLines = SixLines { top :: Bool
                         , right :: Bool
                         , bottom :: Bool
                         , left :: Bool
                         , up :: Bool
                         , totheleft :: Bool
                         } deriving (Eq, Show)

countLine :: SixLines -> (SixLines -> Bool) -> Int
countLine x f =  if f x then 1 else 0

countBoxLines :: SixLines -> Int
countBoxLines x = sum $ map (countLine x) [top, right, bottom, left]

countDotLines :: SixLines -> Int
countDotLines x = sum $ map (countLine x) [up, top, left, totheleft]

slListAll :: [SixLines]
slListAll = [x | t <- [False, True]
               , r <- [False, True]
               , b <- [False, True]
               , l <- [False, True]
               , u <- [False, True]
               , tl <- [False, True]
               , let x = SixLines t r b l u tl
               , countDotLines x `elem` [0, 2]
               ]

slListTop :: [SixLines]
slListTop = [SixLines { top = False
                      , right = False
                      , bottom = b
                      , left = False
                      , up = False
                      , totheleft = False
                      } | b <- [False, True]]

slListRight :: [SixLines]
slListRight = filter (not.top)
            $ filter (not.right)
            $ filter (not.bottom) slListAll

slListBottom :: [SixLines]
slListBottom = filter (not.right)
             $ filter (not.bottom)
             $ filter (not.left) slListAll

slListLeft :: [SixLines]
slListLeft =  [SixLines { top = False
                        , right = r
                        , bottom = False
                        , left = False
                        , up = False
                        , totheleft = False
                        } | r <- [False, True]]

data CellState = CellState { slList :: [SixLines]
                           , visited :: Bool
                           , constraint :: Constraint
                           }
type State =  Array (Int, Int) CellState

stateFromProblem :: Problem -> State
stateFromProblem p = array ((-1, -1), (rn+1, cn+1)) cells
    where ((0, 0), (rn, cn)) = bounds p
          cells = [((r, c), CellState (xform n) False n) | r <- [0..rn], c <- [0..cn], let n = p!(r, c)]
               ++ [((-1, c), CellState slListTop False Unconstrained) | c <- [0 .. cn+1]]
               ++ [((r, cn+1), CellState slListRight False Unconstrained) | r <- [0 .. rn+1]]
               ++ [((rn+1, c), CellState slListBottom False Unconstrained) | c <- [0 .. cn]]
               ++ [((r, -1), CellState slListLeft False Unconstrained) | r <- [-1 .. rn+1]]
          xform Unconstrained = slListAll
          xform (Exactly n) = filter ((== n) . countBoxLines) slListAll

type Direction = (Int, Int)
directions6 :: [Direction] -- right, down, left, up, up&left, down&right
directions6 = [ (0, 1)
             , (1, 0)
             , (0,-1)
             , (-1,0)
             , (-1, -1)
             , (1, 1)
             ]

(.+) :: (Int, Int) -> (Int, Int) -> (Int, Int)
(a, b) .+ (c, d) = (a+c, b+d)

narrow :: Set.Set (Int, Int) -> State -> [State]
narrow seed state = if Set.null seed then [state] else
    let (i@(r,c), seed') = Set.deleteFindMin seed in
      if not (inRange (bounds state) i) 
        then narrow seed' state 
        else do
          let sls = slList $ state!i
          let sls' = filter (match state (r-1, c-1) [(right, up), (bottom, totheleft)])
                   $ filter (match state (r-1, c  ) [(bottom, top), (left, up)])
                   $ filter (match state (r,   c-1) [(top, totheleft), (right, left)])
                   $ filter (match state (r,   c+1) [(totheleft, top), (left, right)])
                   $ filter (match state (r+1, c  ) [(up, left), (top, bottom)])
                   $ filter (match state (r+1, c+1) [(up, right), (totheleft, bottom)])    
                   sls
          if null sls'
             then []
             else if sls' == sls
                     then narrow seed' state
                     else let newSeeds = Set.fromList $ map (i .+) directions6
                          in narrow (Set.union seed' newSeeds) 
                                    (state // [(i, CellState { slList=sls'
                                                             , visited = visited (state!i)
                                                             , constraint = constraint (state!i) })])
                 
match :: State -> (Int, Int) -> [(SixLines->Bool, SixLines->Bool)] -> SixLines -> Bool
match state i fps thiscell = (not (inRange (bounds state) i)) || any ok otherlist
    where otherlist = slList $ state!i
          ok othercell = all pairmatch fps
              where pairmatch (otherf, thisf) = thisf thiscell == otherf othercell

narrowAll :: State -> [State]
narrowAll state = narrow (Set.fromList (indices state)) state

directions4 :: [((Int, Int), SixLines -> Bool)]
directions4 = [ ((0, 1), top)
             , ((1, 0), left)
             , ((0,-1), totheleft)
             , ((-1,0), up)
             ]

visit :: (Int, Int) -> State -> [State]
visit i state = if inRange (bounds state) i && not (visited (cell))
                   then [state // [(i, CellState { slList = slList cell
                                                 , visited = True
                                                 , constraint = constraint cell
                                                 })]]
                   else []
    where cell = state!i

solve :: Problem -> [State]
solve problem = do
  state <- narrowAll $ stateFromProblem problem
  solve' (startingPositions state) state

solve' :: [(Int, Int)] -> State -> [State]
solve' [] _ = []
solve' (i:is) state = solve'' i state ++ solve' is state'
    where state' = state // [(i, CellState {slList = sll', visited = v, constraint = cstr})]
          CellState sll v cstr = state!i
          sll' = filter ((==0).countDotLines) sll


solve'' :: (Int, Int) -> State -> [State]
solve'' start state = maybeList $ find (not.null) $ map (step start start state) directions4
    where maybeList (Just x) = x
          maybeList Nothing  = []

solve''' :: (Int, Int) -> (Int, Int) -> State -> [State]
solve''' goal pos state = concatMap (step goal pos state) directions4

step :: (Int, Int) -> (Int, Int) -> State -> ((Int, Int), SixLines -> Bool) -> [State]
step goal pos state (dir, line) = do
     let pos' = pos .+ dir
     state' <- visit pos' state
     let sls = slList $ state'!pos
     let sls' = filter line sls
     when (null sls') []
     state'' <- if sls' == sls 
                  then [state']
                  else narrow (Set.fromList $ map (pos .+) directions6) 
                            $ state' // [(pos, CellState sls' (visited (state'!pos)) (constraint (state'!pos)))]
     if (pos' == goal)
        then zeroRemainingLines state''
        else solve''' goal pos' state''

zeroRemainingLines :: State -> [State]
zeroRemainingLines state = foldM zero state (indices state) >>= narrowAll
    where zero s i = if visited (s!i)
                        then [s]
                        else do
                          let sls = slList (s!i)
                          let sls' = filter ((==0).countDotLines) sls
                          when (null sls') []
                          [s // [(i, CellState sls' False (constraint (s!i)))]]

startingPositions :: State -> [(Int, Int)]
startingPositions state = if null s then indices state else [head s]
  where s = filter lineAtDot $ indices state
        lineAtDot i = let (CellState sls _ _) = state!i
                      in all ((==2) . countDotLines) sls

showState ::State -> String
showState state = concat $ map twoLines [r0 .. rn]
  where ((r0, c0), (rn, cn)) = bounds state
        twoLines r = unlines [oddLine r, evenLine r]
        oddLine r = concat $ map (oddPair r) [c0 .. cn]
        oddPair r c = dot r c ++ hLine r c
        dot r c = yesNoMaybe ((==0).countDotLines) r c " " "+" "?"
        hLine r c = yesNoMaybe top r c "-" " " "?"
        evenLine r = concat $ map (evenPair r) [c0 .. cn]
        evenPair r c = vLine r c ++ square r c
        vLine r c = yesNoMaybe left r c "|" " " "?"
        square r c = show (constraint (state!(r, c)))
        yesNoMaybe f r c y n m = let sll = slList (state!(r, c)) 
                                 in if all f sll then y else if all (not.f) sll then n else m

main :: IO ()
main = do
     args <- getArgs
     case args of
          [filename, number] -> do
                     s <- readFile filename
                     work s (read number)
          [filename] -> do
                     s <- readFile filename
                     work s 2
          [] -> work sampleProblemString 2
          _  -> error "Too many arguments."
  where work s n = case readProblem s of
             Left e -> putStrLn e
             Right p -> do
                   putStrLn $ "Showing " ++ (if n == 0 then "all" else show n) ++ " solutions."
                   let solutions = solve p
                   let display
                         | n == 0 = solutions
                         | otherwise = take n solutions
                   putStr $ concatMap showState display
                   putStrLn $ "Total number of solutions: " ++ show (length solutions)

-- stuff for interactive experiments

sampleProblemString :: String
sampleProblemString = unlines [".3.112.2.."
                              ,".3..3.1312"
                              ,"22.1......"
                              ,".3..3..2.2"
                              ,"2.....2.21"
                              ,"31.3.....3"
                              ,"2.2..3..2."
                              ,"......1.32"
                              ,"2220.3..3."
                              ,"..3.122.2."
                              ]

sampleProblem :: Problem
sampleProblem = case readProblem sampleProblemString of 
  Right x -> x
  Left _ -> undefined -- can't happen

