{-# LANGUAGE UndecidableInstances #-}
module Luna.Pass.Transform.Desugar.RemoveGrouped where

import Prologue

import qualified Data.Graph.Data.Component.List      as ComponentList
import qualified Data.Set                            as Set
import qualified Luna.IR                             as IR
import qualified Luna.IR.Layer                       as Layer
import qualified Luna.Pass                           as Pass
import qualified Luna.Pass.Attr                      as Attr
import qualified Luna.Pass.Basic                     as Pass
import Luna.Pass.Data.Root

data RemoveGrouped

type instance Pass.Spec RemoveGrouped t = RemoveGroupedSpec t
type family RemoveGroupedSpec t where
    RemoveGroupedSpec (Pass.In  Pass.Attrs) = '[Root]
    RemoveGroupedSpec (Pass.Out Pass.Attrs) = '[Root]
    RemoveGroupedSpec t = Pass.BasicPassSpec t

instance (Pass.Interface RemoveGrouped (Pass.Pass stage RemoveGrouped),
          IR.DeleteSubtree (Pass.Pass stage RemoveGrouped))
      => Pass.Definition stage RemoveGrouped where
    definition = do
        Root root <- Attr.get
        newRoot   <- runRemoveGrouped root
        Attr.put $ Root newRoot

runRemoveGrouped :: (Pass.Interface RemoveGrouped m, IR.DeleteSubtree m)
                 => IR.SomeTerm -> m IR.SomeTerm
runRemoveGrouped root = do
    inputEdges <- IR.inputs root
    ComponentList.mapM_ (runRemoveGrouped <=< Layer.read @IR.Source) inputEdges
    model <- Layer.read @IR.Model root
    case model of
        IR.UniTermGrouped (IR.Grouped g) -> do
            g' <- Layer.read @IR.Source g
            IR.substitute g' root
            IR.deleteSubtreeWithWhitelist (Set.singleton g') root
            return g'
        _ -> return root
