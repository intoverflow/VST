Require Import floyd.base.
Require Import floyd.assert_lemmas.
Require Import floyd.client_lemmas.
Require Import floyd.nested_field_lemmas.
Require Import type_induction.
Require floyd.aggregate_type. Import floyd.aggregate_type.aggregate_type.
Require Import floyd.reptype_lemmas.
Require Import floyd.proj_reptype_lemmas.
Require Import floyd.jmeq_lemmas.
Require Import Coq.Logic.JMeq.
Require Import Coq.Classes.RelationClasses.

Section MULTI_HOLES.

Context {cs: compspecs}.
Context {csl: compspecs_legal cs}.

Inductive holes : Type :=
  | FullUpdate
  | SemiUpdate: (gfield -> holes) -> holes
  | Stable
  | Invalid.

Fixpoint nested_field_type3 t gfs :=
  match gfs with
  | nil => t
  | gf :: gfs0 => nested_field_type3 (gfield_type t gf) gfs0
  end.

(* reverse gfs order *)
Definition holes_subs t := forall gfs, reptype (nested_field_type3 t gfs).

Lemma nested_field_type2_ind': forall t gf gfs, nested_field_type2 t (gfs ++ gf :: nil) = nested_field_type2 (gfield_type t gf) gfs.
Proof.
  intros.
  rewrite <- nested_field_type2_nested_field_type2.
  rewrite nested_field_type2_ind with (gfs0 := gf :: nil).
  reflexivity.
Defined.

Lemma nested_field_type3_spec: forall t gfs, nested_field_type3 t gfs = nested_field_type2 t (rev gfs).
Proof.
  intros.
  revert t; induction gfs; intros.
  + auto.
  + simpl.
    rewrite nested_field_type2_ind'.
    rewrite IHgfs.
    auto.
Defined.

Lemma nested_field_type3_rev_spec: forall t gfs, nested_field_type3 t (rev gfs) = nested_field_type2 t gfs.
Proof.
  intros.
  rewrite <- (rev_involutive gfs) at 2.
  apply nested_field_type3_spec.
Defined.

Definition gfield_holes (h: holes) (gf: gfield): holes :=
  match h with
  | FullUpdate => Invalid
  | SemiUpdate subl => subl gf
  | Stable => Stable
  | Invalid => Invalid
  end.

Fixpoint nested_field_holes (h: holes) (gfs: list gfield) : holes :=
  match gfs with
  | nil => h
  | gf :: gfs0 => gfield_holes (nested_field_holes h gfs0) gf
  end.

Definition gfield_subs {t} (subs: holes_subs t) (gf: gfield): holes_subs (gfield_type t gf) :=
  fun gfs => subs (gf :: gfs).

Definition holes_subs_equiv {t} h (subs1 subs2: holes_subs t) : Prop :=
  forall gfs, legal_nested_field t gfs -> nested_field_holes h gfs = FullUpdate -> subs1 (rev gfs) = subs2 (rev gfs).

Definition reptype_with_holes (t: type) (h: holes): Type := reptype t.

Definition reptype_with_holes_equiv {t: type} {h: holes} (v0 v1: reptype_with_holes t h): Prop :=
  forall gfs, legal_nested_field t gfs -> nested_field_holes h gfs = Stable -> proj_reptype t gfs v0 = proj_reptype t gfs v1.

Definition proj_except_holes (t: type) (h: holes) (v: reptype t) : reptype_with_holes t h := v.

Definition ListType_map {X: Type} {F F0: X -> Type} {l: list X}
  (f: ListType (map (fun x => F x -> F0 x) l)): ListType (map F l) -> ListType (map F0 l).
Proof.
  intros.
  induction l; simpl in *.
  + exact Nil.
  + inversion f; inversion X0; subst.
    exact (Cons (a0 a1) (IHl b b0)).
Defined.

Definition legal_holes: forall (t: type) (h: holes), Prop :=
  func_type (fun _ => holes -> Prop)
    (fun t h =>
       match h with
       | FullUpdate | Stable => True
       | SemiUpdate _ | Invalid => False
       end)
    (fun t n a F h => 
       match h with
       | FullUpdate | Stable => True
       | SemiUpdate subl => forall i, 0 <= i < n -> F (subl (ArraySubsc i))
       | Invalid => False
       end)
    (fun id a F h =>
       match h with
       | FullUpdate | Stable => True
       | SemiUpdate subl =>
          fold_right and True 
           (decay (ListType_map F (ListTypeGen (fun _ => holes) (fun it => subl (StructField (fst it))) _)))
       | Invalid => False
       end)
    (fun id a F h =>
       match h with
       | FullUpdate | Stable => True
       | SemiUpdate subl =>
          exists i,
          fold_right and (in_members i (co_members (get_co id)))
           (decay (ListType_map 
             (ListTypeGen
               (fun _ => (holes -> Prop) -> Prop)
               (fun it F => if ident_eq i (fst it)
                            then F (subl (UnionField (fst it)))
                            else subl (UnionField (fst it)) = Invalid) _)
             F))
       | Invalid => False
       end).

Fixpoint get_union_field (subl: gfield -> holes) (m: members) (default: ident): ident :=
  match m with
  | nil => default
  | (i, t) :: m0 => match subl (UnionField i) with | Invalid => get_union_field subl m0 default | _ => i end
  end.

Definition get_union_member subl m :=
  let i := get_union_field subl m 1%positive in
  (i, field_type i m).

Definition reinitiate_compact_sum {A} {F: A -> Type} {l: list A} (v: compact_sum (map F l)) (a: A) (init: forall a, F a) (H: forall a0 a1: A, {a0 = a1} + {a0 <> a1}) :=
  compact_sum_gen
   (fun a0 => if H a a0 then true else false)
   (fun a0 => proj_compact_sum a0 l v (init a0) H)
  l.

Definition replace_reptype: forall (t: type) (h: holes) (subs: holes_subs t) (v: reptype t), reptype t :=
  func_type (fun t => holes -> holes_subs t -> reptype t -> reptype t)
    (fun t h subs v =>
       match h with
       | FullUpdate => subs nil
       | _ => v
       end)
    (fun t n a F h subs v =>
       match h with
       | FullUpdate => subs nil
       | SemiUpdate subl =>
         @fold_reptype _ _ (Tarray t n a) 
           (zl_gen 0 n
             (fun i => F (subl (ArraySubsc i))
                         (fun gfs => subs (ArraySubsc i :: gfs))
                         (zl_nth i (unfold_reptype v))))
       | StableOrInvalid => v
       end)
    (fun id a F h subs v =>
       match h with
       | FullUpdate => subs nil
       | SemiUpdate subl =>
         @fold_reptype _ _ (Tstruct id a)
           (compact_prod_map _
             (ListType_map
               (ListType_map F
                 (ListTypeGen (fun _ => holes) (fun it => subl (StructField (fst it))) _))
               (ListTypeGen (fun it => holes_subs (field_type (fst it) (co_members (get_co id))))
                            (fun it gfs => subs (StructField (fst it) :: gfs)) _))
             (unfold_reptype v))
       | StableOrInvalid => v
       end)
    (fun id a F h subs v =>
       match h with
       | FullUpdate => subs nil
       | SemiUpdate subl =>
         @fold_reptype _ _ (Tunion id a)
           (compact_sum_map _
             (ListType_map
               (ListType_map F
                 (ListTypeGen (fun _ => holes) (fun it => subl (StructField (fst it))) _))
               (ListTypeGen (fun it => holes_subs (field_type (fst it) (co_members (get_co id))))
                            (fun it gfs => subs (UnionField (fst it) :: gfs)) _))
             (reinitiate_compact_sum
               (unfold_reptype v)
               (get_union_member subl (co_members (get_co id)))
               (fun _ => default_val _)
               member_dec
               ))
       | StableOrInvalid => v
       end).

Definition refill_reptype {t h} (v: reptype_with_holes t h) (subs: holes_subs t) := replace_reptype t h subs v. 

Lemma replace_stable: forall t h subs v gfs,
  legal_holes t h ->
  legal_nested_field t gfs ->
  nested_field_holes h gfs = Stable ->
  proj_reptype t gfs (replace_reptype t h subs v) = proj_reptype t gfs v.
Admitted.

Lemma replace_change: forall t h subs v gfs,
  legal_holes t h ->
  legal_nested_field t gfs ->
  nested_field_holes h gfs = FullUpdate ->
  proj_reptype t gfs (replace_reptype t h subs v) =
  eq_rect_r reptype (subs (rev gfs)) (eq_sym (nested_field_type3_rev_spec _ _)).
Admitted.

Lemma replace_proj_self: forall t h v gfs,
  legal_holes t h ->
  legal_nested_field t gfs ->
  type_is_by_value (nested_field_type2 t gfs) = true ->
  proj_reptype t gfs (replace_reptype t h (fun rgfs => eq_rect_r reptype (proj_reptype t (rev rgfs) v) (nested_field_type3_spec _ _)) v) = proj_reptype t gfs v \/
  proj_reptype t gfs (replace_reptype t h (fun rgfs => eq_rect_r reptype (proj_reptype t (rev rgfs) v) (nested_field_type3_spec _ _)) v) = default_val _.
Admitted.

Lemma refill_proj_except: forall t h (v: reptype t) (v0: holes_subs t),
  refill_reptype (proj_except_holes t h v) v0 = replace_reptype t h v0 v.
Proof. auto. Qed.

Instance Equiv_reptype_with_holes t h : Equivalence (@reptype_with_holes_equiv t h).
  unfold reptype_with_holes_equiv.
  split.
  + unfold Reflexive.
    intros.
    auto.
  + unfold Symmetric.
    intros.
    symmetry.
    auto.
  + unfold Transitive.
    intros.
    specialize (H gfs H1 H2).
    specialize (H0 gfs H1 H2).
    congruence.
Defined.

Instance Equiv_holes_subs t h: Equivalence (@holes_subs_equiv t h).
  unfold holes_subs_equiv.
  split.
  + unfold Reflexive.
    intros.
    auto.
  + unfold Symmetric.
    intros.
    symmetry.
    auto.
  + unfold Transitive.
    intros.
    specialize (H gfs H1 H2).
    specialize (H0 gfs H1 H2).
    congruence.
Defined.

Require Import Coq.Classes.Morphisms.

Instance Proper_refill_1 t h v0: Proper ((@reptype_with_holes_equiv t h) ==> (@eq (reptype t))) (fun v: reptype_with_holes t h => refill_reptype v v0).
Proof.
  admit.
Defined.

(* (* dont know which version is better. This one is more concise but its correctness is based on function extensionality *)
Instance Proper_refill_1 t h: Proper ((@reptype_with_holes_equiv t h) ==> (@eq (holes_subs t -> reptype t))) (@refill_reptype t h).
Proof.
  admit.
Defined.
*)

Instance Proper_refill_2 t h (v: reptype_with_holes t h) : Proper ((@holes_subs_equiv t h) ==> (@eq (reptype t))) (refill_reptype v).
Proof.
  admit.
Defined.

Instance Proper_replace t h v: Proper ((@holes_subs_equiv t h) ==> (@eq (reptype t))) (fun v0 => replace_reptype t h v0 v).
Proof.
  admit.
Defined.

End MULTI_HOLES.

Section SINGLE_HOLE.

Context {cs: compspecs}.
Context {csl: compspecs_legal cs}.

Lemma gfield_dec: forall (gf0 gf1: gfield), {gf0 = gf1} + {gf0 <> gf1}.
Proof.
  intros.
  destruct gf0, gf1; try solve [right; congruence].
  + destruct (zeq i i0); [left | right]; congruence.
  + destruct (Pos.eq_dec i i0); [left | right]; congruence.
  + destruct (Pos.eq_dec i i0); [left | right]; congruence.
Defined.

Fixpoint singleton_hole_rec (rgfs: list gfield) : holes := 
  match rgfs with
  | nil => FullUpdate
  | gf :: rgfs0 => 
    match gf with
    | ArraySubsc _
    | StructField _ => SemiUpdate (fun gf0 => if gfield_dec gf gf0 then singleton_hole_rec rgfs0 else Stable)
    | UnionField _ => SemiUpdate (fun gf0 => if gfield_dec gf gf0 then singleton_hole_rec rgfs0 else Invalid)
    end
  end.

Definition singleton_hole (gfs: list gfield) : holes := singleton_hole_rec (rev gfs).

Lemma rgfs_dec: forall rgfs0 rgfs1: list gfield, {rgfs0 = rgfs1} + {rgfs0 <> rgfs1}.
Proof.
  apply list_eq_dec.
  apply gfield_dec.
Defined.

Definition singleton_subs t gfs (v: reptype (nested_field_type2 t gfs)): holes_subs t.
  rewrite <- nested_field_type3_rev_spec in v.
  intro rgfs.
  destruct (rgfs_dec rgfs (rev gfs)).
  + subst.
    exact v.
  + exact (default_val _).
Qed.

Definition proj_except_holes_1 t gfs v: reptype_with_holes t (singleton_hole gfs) :=
  proj_except_holes t (singleton_hole gfs) v.

Definition refill_reptype_1 t gfs (v: reptype_with_holes t (singleton_hole gfs)) (v0: reptype (nested_field_type2 t gfs)) :=
  refill_reptype v (singleton_subs t gfs v0).

Definition replace_reptype_1 t gfs (v: reptype t) (v0: reptype (nested_field_type2 t gfs)) :=
  replace_reptype t (singleton_hole gfs) (singleton_subs t gfs v0) v.

End SINGLE_HOLE.

Section Test.

Definition cd1 := Composite 101%positive Struct ((1%positive, tint) :: (2%positive, tint) :: nil) noattr.
Definition cd2 := Composite 102%positive Struct ((3%positive, Tstruct 101%positive noattr) ::
                                 (4%positive, Tstruct 101%positive noattr) ::
                                 (5%positive, Tpointer (Tstruct 101%positive noattr) noattr) :: nil) noattr.
Definition cenv := match build_composite_env (cd1 :: cd2 :: nil) with Errors.OK env => env | _ => PTree.empty _ end.

Instance cs: compspecs.
  apply (mkcompspecs cenv).
  apply build_composite_env_consistent with (defs := cd1 :: cd2 :: nil).
  reflexivity.
Defined.

Instance csl: compspecs_legal cs.
  split.
  + intros ? ? ?.
    apply PTree.elements_correct in H.
    revert H.
    change co with (snd (id, co)) at 2.
    forget (id, co) as ele.
    revert ele.
    apply Forall_forall.
    assert (8 >= 8) by omega.
    assert (4 >= 4) by omega.
    repeat constructor; unfold composite_legal_alignas; assumption.
  + intros ? ? ?.
    apply PTree.elements_correct in H.
    revert H.
    change co with (snd (id, co)) at 2.
    forget (id, co) as ele.
    revert ele.
    apply Forall_forall.
    repeat constructor; unfold composite_legal_alignas; reflexivity.
Defined.

Definition t1 := Tstruct 101%positive noattr.
Definition t2 := Tstruct 102%positive noattr.
Definition v1: reptype t1 := (Vint Int.zero, Vint Int.one).
Definition v2: reptype t2 := ((Vint Int.zero, Vint Int.one), ((Vint Int.zero, Vint Int.one), Vundef)).
(*
Eval vm_compute in (reptype t2).
Eval vm_compute in (proj_reptype t1 (StructField 1%positive :: nil) v1).
*)
Goal proj_reptype t1 (StructField 1%positive :: nil) v1 = Vint Int.zero.
reflexivity.
Qed.

Goal replace_reptype_1 t2 (StructField 3%positive :: nil) v2 (Vint Int.one, Vint Int.one) =
((Vint Int.one, Vint Int.one), ((Vint Int.zero, Vint Int.one), Vundef)).
reflexivity.

(*
Transparent peq.
cbv [proj_struct proj_compact_prod proj_union proj_compact_sum get_co
field_type fieldlist.field_type2 Ctypes.field_type
list_rect member_dec ident_eq peq Pos.eq_dec BinNums.positive_rec positive_rect 
sumbool_rec sumbool_rect bool_dec bool_rec bool_rect option_rec option_rect
eq_rect_r eq_rect eq_rec_r eq_rec eq_sym eq_trans f_equal
type_eq type_rec type_rect typelist_eq typelist_rec typelist_rect
intsize_rec intsize_rect signedness_rec signedness_rect floatsize_rec floatsize_rect attr_rec attr_rect
tvoid tschar tuchar tshort tushort tint
tuint tbool tlong tulong tfloat tdouble tptr tarray noattr].
*)
Qed.

End Test.