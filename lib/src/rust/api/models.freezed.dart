// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$AlbumChoice {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String albumId) existing,
    required TResult Function(String title, List<String> artists) new_,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String albumId)? existing,
    TResult? Function(String title, List<String> artists)? new_,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String albumId)? existing,
    TResult Function(String title, List<String> artists)? new_,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AlbumChoice_Existing value) existing,
    required TResult Function(AlbumChoice_New value) new_,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AlbumChoice_Existing value)? existing,
    TResult? Function(AlbumChoice_New value)? new_,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AlbumChoice_Existing value)? existing,
    TResult Function(AlbumChoice_New value)? new_,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AlbumChoiceCopyWith<$Res> {
  factory $AlbumChoiceCopyWith(
    AlbumChoice value,
    $Res Function(AlbumChoice) then,
  ) = _$AlbumChoiceCopyWithImpl<$Res, AlbumChoice>;
}

/// @nodoc
class _$AlbumChoiceCopyWithImpl<$Res, $Val extends AlbumChoice>
    implements $AlbumChoiceCopyWith<$Res> {
  _$AlbumChoiceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$AlbumChoice_ExistingImplCopyWith<$Res> {
  factory _$$AlbumChoice_ExistingImplCopyWith(
    _$AlbumChoice_ExistingImpl value,
    $Res Function(_$AlbumChoice_ExistingImpl) then,
  ) = __$$AlbumChoice_ExistingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String albumId});
}

/// @nodoc
class __$$AlbumChoice_ExistingImplCopyWithImpl<$Res>
    extends _$AlbumChoiceCopyWithImpl<$Res, _$AlbumChoice_ExistingImpl>
    implements _$$AlbumChoice_ExistingImplCopyWith<$Res> {
  __$$AlbumChoice_ExistingImplCopyWithImpl(
    _$AlbumChoice_ExistingImpl _value,
    $Res Function(_$AlbumChoice_ExistingImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? albumId = null}) {
    return _then(
      _$AlbumChoice_ExistingImpl(
        albumId: null == albumId
            ? _value.albumId
            : albumId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$AlbumChoice_ExistingImpl extends AlbumChoice_Existing {
  const _$AlbumChoice_ExistingImpl({required this.albumId}) : super._();

  @override
  final String albumId;

  @override
  String toString() {
    return 'AlbumChoice.existing(albumId: $albumId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AlbumChoice_ExistingImpl &&
            (identical(other.albumId, albumId) || other.albumId == albumId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, albumId);

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AlbumChoice_ExistingImplCopyWith<_$AlbumChoice_ExistingImpl>
  get copyWith =>
      __$$AlbumChoice_ExistingImplCopyWithImpl<_$AlbumChoice_ExistingImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String albumId) existing,
    required TResult Function(String title, List<String> artists) new_,
  }) {
    return existing(albumId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String albumId)? existing,
    TResult? Function(String title, List<String> artists)? new_,
  }) {
    return existing?.call(albumId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String albumId)? existing,
    TResult Function(String title, List<String> artists)? new_,
    required TResult orElse(),
  }) {
    if (existing != null) {
      return existing(albumId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AlbumChoice_Existing value) existing,
    required TResult Function(AlbumChoice_New value) new_,
  }) {
    return existing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AlbumChoice_Existing value)? existing,
    TResult? Function(AlbumChoice_New value)? new_,
  }) {
    return existing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AlbumChoice_Existing value)? existing,
    TResult Function(AlbumChoice_New value)? new_,
    required TResult orElse(),
  }) {
    if (existing != null) {
      return existing(this);
    }
    return orElse();
  }
}

abstract class AlbumChoice_Existing extends AlbumChoice {
  const factory AlbumChoice_Existing({required final String albumId}) =
      _$AlbumChoice_ExistingImpl;
  const AlbumChoice_Existing._() : super._();

  String get albumId;

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AlbumChoice_ExistingImplCopyWith<_$AlbumChoice_ExistingImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$AlbumChoice_NewImplCopyWith<$Res> {
  factory _$$AlbumChoice_NewImplCopyWith(
    _$AlbumChoice_NewImpl value,
    $Res Function(_$AlbumChoice_NewImpl) then,
  ) = __$$AlbumChoice_NewImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String title, List<String> artists});
}

/// @nodoc
class __$$AlbumChoice_NewImplCopyWithImpl<$Res>
    extends _$AlbumChoiceCopyWithImpl<$Res, _$AlbumChoice_NewImpl>
    implements _$$AlbumChoice_NewImplCopyWith<$Res> {
  __$$AlbumChoice_NewImplCopyWithImpl(
    _$AlbumChoice_NewImpl _value,
    $Res Function(_$AlbumChoice_NewImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? title = null, Object? artists = null}) {
    return _then(
      _$AlbumChoice_NewImpl(
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        artists: null == artists
            ? _value._artists
            : artists // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// @nodoc

class _$AlbumChoice_NewImpl extends AlbumChoice_New {
  const _$AlbumChoice_NewImpl({
    required this.title,
    required final List<String> artists,
  }) : _artists = artists,
       super._();

  @override
  final String title;
  final List<String> _artists;
  @override
  List<String> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  @override
  String toString() {
    return 'AlbumChoice.new_(title: $title, artists: $artists)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AlbumChoice_NewImpl &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other._artists, _artists));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    const DeepCollectionEquality().hash(_artists),
  );

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AlbumChoice_NewImplCopyWith<_$AlbumChoice_NewImpl> get copyWith =>
      __$$AlbumChoice_NewImplCopyWithImpl<_$AlbumChoice_NewImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String albumId) existing,
    required TResult Function(String title, List<String> artists) new_,
  }) {
    return new_(title, artists);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String albumId)? existing,
    TResult? Function(String title, List<String> artists)? new_,
  }) {
    return new_?.call(title, artists);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String albumId)? existing,
    TResult Function(String title, List<String> artists)? new_,
    required TResult orElse(),
  }) {
    if (new_ != null) {
      return new_(title, artists);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AlbumChoice_Existing value) existing,
    required TResult Function(AlbumChoice_New value) new_,
  }) {
    return new_(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AlbumChoice_Existing value)? existing,
    TResult? Function(AlbumChoice_New value)? new_,
  }) {
    return new_?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AlbumChoice_Existing value)? existing,
    TResult Function(AlbumChoice_New value)? new_,
    required TResult orElse(),
  }) {
    if (new_ != null) {
      return new_(this);
    }
    return orElse();
  }
}

abstract class AlbumChoice_New extends AlbumChoice {
  const factory AlbumChoice_New({
    required final String title,
    required final List<String> artists,
  }) = _$AlbumChoice_NewImpl;
  const AlbumChoice_New._() : super._();

  String get title;
  List<String> get artists;

  /// Create a copy of AlbumChoice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AlbumChoice_NewImplCopyWith<_$AlbumChoice_NewImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$CoverArtEdit {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() remove,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    replace,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? remove,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? remove,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CoverArtEdit_Keep value) keep,
    required TResult Function(CoverArtEdit_Remove value) remove,
    required TResult Function(CoverArtEdit_Replace value) replace,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CoverArtEdit_Keep value)? keep,
    TResult? Function(CoverArtEdit_Remove value)? remove,
    TResult? Function(CoverArtEdit_Replace value)? replace,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CoverArtEdit_Keep value)? keep,
    TResult Function(CoverArtEdit_Remove value)? remove,
    TResult Function(CoverArtEdit_Replace value)? replace,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CoverArtEditCopyWith<$Res> {
  factory $CoverArtEditCopyWith(
    CoverArtEdit value,
    $Res Function(CoverArtEdit) then,
  ) = _$CoverArtEditCopyWithImpl<$Res, CoverArtEdit>;
}

/// @nodoc
class _$CoverArtEditCopyWithImpl<$Res, $Val extends CoverArtEdit>
    implements $CoverArtEditCopyWith<$Res> {
  _$CoverArtEditCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$CoverArtEdit_KeepImplCopyWith<$Res> {
  factory _$$CoverArtEdit_KeepImplCopyWith(
    _$CoverArtEdit_KeepImpl value,
    $Res Function(_$CoverArtEdit_KeepImpl) then,
  ) = __$$CoverArtEdit_KeepImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$CoverArtEdit_KeepImplCopyWithImpl<$Res>
    extends _$CoverArtEditCopyWithImpl<$Res, _$CoverArtEdit_KeepImpl>
    implements _$$CoverArtEdit_KeepImplCopyWith<$Res> {
  __$$CoverArtEdit_KeepImplCopyWithImpl(
    _$CoverArtEdit_KeepImpl _value,
    $Res Function(_$CoverArtEdit_KeepImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$CoverArtEdit_KeepImpl extends CoverArtEdit_Keep {
  const _$CoverArtEdit_KeepImpl() : super._();

  @override
  String toString() {
    return 'CoverArtEdit.keep()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$CoverArtEdit_KeepImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() remove,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    replace,
  }) {
    return keep();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? remove,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
  }) {
    return keep?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? remove,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CoverArtEdit_Keep value) keep,
    required TResult Function(CoverArtEdit_Remove value) remove,
    required TResult Function(CoverArtEdit_Replace value) replace,
  }) {
    return keep(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CoverArtEdit_Keep value)? keep,
    TResult? Function(CoverArtEdit_Remove value)? remove,
    TResult? Function(CoverArtEdit_Replace value)? replace,
  }) {
    return keep?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CoverArtEdit_Keep value)? keep,
    TResult Function(CoverArtEdit_Remove value)? remove,
    TResult Function(CoverArtEdit_Replace value)? replace,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep(this);
    }
    return orElse();
  }
}

abstract class CoverArtEdit_Keep extends CoverArtEdit {
  const factory CoverArtEdit_Keep() = _$CoverArtEdit_KeepImpl;
  const CoverArtEdit_Keep._() : super._();
}

/// @nodoc
abstract class _$$CoverArtEdit_RemoveImplCopyWith<$Res> {
  factory _$$CoverArtEdit_RemoveImplCopyWith(
    _$CoverArtEdit_RemoveImpl value,
    $Res Function(_$CoverArtEdit_RemoveImpl) then,
  ) = __$$CoverArtEdit_RemoveImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$CoverArtEdit_RemoveImplCopyWithImpl<$Res>
    extends _$CoverArtEditCopyWithImpl<$Res, _$CoverArtEdit_RemoveImpl>
    implements _$$CoverArtEdit_RemoveImplCopyWith<$Res> {
  __$$CoverArtEdit_RemoveImplCopyWithImpl(
    _$CoverArtEdit_RemoveImpl _value,
    $Res Function(_$CoverArtEdit_RemoveImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$CoverArtEdit_RemoveImpl extends CoverArtEdit_Remove {
  const _$CoverArtEdit_RemoveImpl() : super._();

  @override
  String toString() {
    return 'CoverArtEdit.remove()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CoverArtEdit_RemoveImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() remove,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    replace,
  }) {
    return remove();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? remove,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
  }) {
    return remove?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? remove,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
    required TResult orElse(),
  }) {
    if (remove != null) {
      return remove();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CoverArtEdit_Keep value) keep,
    required TResult Function(CoverArtEdit_Remove value) remove,
    required TResult Function(CoverArtEdit_Replace value) replace,
  }) {
    return remove(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CoverArtEdit_Keep value)? keep,
    TResult? Function(CoverArtEdit_Remove value)? remove,
    TResult? Function(CoverArtEdit_Replace value)? replace,
  }) {
    return remove?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CoverArtEdit_Keep value)? keep,
    TResult Function(CoverArtEdit_Remove value)? remove,
    TResult Function(CoverArtEdit_Replace value)? replace,
    required TResult orElse(),
  }) {
    if (remove != null) {
      return remove(this);
    }
    return orElse();
  }
}

abstract class CoverArtEdit_Remove extends CoverArtEdit {
  const factory CoverArtEdit_Remove() = _$CoverArtEdit_RemoveImpl;
  const CoverArtEdit_Remove._() : super._();
}

/// @nodoc
abstract class _$$CoverArtEdit_ReplaceImplCopyWith<$Res> {
  factory _$$CoverArtEdit_ReplaceImplCopyWith(
    _$CoverArtEdit_ReplaceImpl value,
    $Res Function(_$CoverArtEdit_ReplaceImpl) then,
  ) = __$$CoverArtEdit_ReplaceImplCopyWithImpl<$Res>;
  @useResult
  $Res call({
    String originalSourcePath,
    String croppedSourcePath,
    ArtworkCropRectData crop,
  });
}

/// @nodoc
class __$$CoverArtEdit_ReplaceImplCopyWithImpl<$Res>
    extends _$CoverArtEditCopyWithImpl<$Res, _$CoverArtEdit_ReplaceImpl>
    implements _$$CoverArtEdit_ReplaceImplCopyWith<$Res> {
  __$$CoverArtEdit_ReplaceImplCopyWithImpl(
    _$CoverArtEdit_ReplaceImpl _value,
    $Res Function(_$CoverArtEdit_ReplaceImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? originalSourcePath = null,
    Object? croppedSourcePath = null,
    Object? crop = null,
  }) {
    return _then(
      _$CoverArtEdit_ReplaceImpl(
        originalSourcePath: null == originalSourcePath
            ? _value.originalSourcePath
            : originalSourcePath // ignore: cast_nullable_to_non_nullable
                  as String,
        croppedSourcePath: null == croppedSourcePath
            ? _value.croppedSourcePath
            : croppedSourcePath // ignore: cast_nullable_to_non_nullable
                  as String,
        crop: null == crop
            ? _value.crop
            : crop // ignore: cast_nullable_to_non_nullable
                  as ArtworkCropRectData,
      ),
    );
  }
}

/// @nodoc

class _$CoverArtEdit_ReplaceImpl extends CoverArtEdit_Replace {
  const _$CoverArtEdit_ReplaceImpl({
    required this.originalSourcePath,
    required this.croppedSourcePath,
    required this.crop,
  }) : super._();

  @override
  final String originalSourcePath;
  @override
  final String croppedSourcePath;
  @override
  final ArtworkCropRectData crop;

  @override
  String toString() {
    return 'CoverArtEdit.replace(originalSourcePath: $originalSourcePath, croppedSourcePath: $croppedSourcePath, crop: $crop)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CoverArtEdit_ReplaceImpl &&
            (identical(other.originalSourcePath, originalSourcePath) ||
                other.originalSourcePath == originalSourcePath) &&
            (identical(other.croppedSourcePath, croppedSourcePath) ||
                other.croppedSourcePath == croppedSourcePath) &&
            (identical(other.crop, crop) || other.crop == crop));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, originalSourcePath, croppedSourcePath, crop);

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CoverArtEdit_ReplaceImplCopyWith<_$CoverArtEdit_ReplaceImpl>
  get copyWith =>
      __$$CoverArtEdit_ReplaceImplCopyWithImpl<_$CoverArtEdit_ReplaceImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() remove,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    replace,
  }) {
    return replace(originalSourcePath, croppedSourcePath, crop);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? remove,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
  }) {
    return replace?.call(originalSourcePath, croppedSourcePath, crop);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? remove,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    replace,
    required TResult orElse(),
  }) {
    if (replace != null) {
      return replace(originalSourcePath, croppedSourcePath, crop);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CoverArtEdit_Keep value) keep,
    required TResult Function(CoverArtEdit_Remove value) remove,
    required TResult Function(CoverArtEdit_Replace value) replace,
  }) {
    return replace(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CoverArtEdit_Keep value)? keep,
    TResult? Function(CoverArtEdit_Remove value)? remove,
    TResult? Function(CoverArtEdit_Replace value)? replace,
  }) {
    return replace?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CoverArtEdit_Keep value)? keep,
    TResult Function(CoverArtEdit_Remove value)? remove,
    TResult Function(CoverArtEdit_Replace value)? replace,
    required TResult orElse(),
  }) {
    if (replace != null) {
      return replace(this);
    }
    return orElse();
  }
}

abstract class CoverArtEdit_Replace extends CoverArtEdit {
  const factory CoverArtEdit_Replace({
    required final String originalSourcePath,
    required final String croppedSourcePath,
    required final ArtworkCropRectData crop,
  }) = _$CoverArtEdit_ReplaceImpl;
  const CoverArtEdit_Replace._() : super._();

  String get originalSourcePath;
  String get croppedSourcePath;
  ArtworkCropRectData get crop;

  /// Create a copy of CoverArtEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CoverArtEdit_ReplaceImplCopyWith<_$CoverArtEdit_ReplaceImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PlaylistVisualEdit {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() initials,
    required TResult Function(String key) icon,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    image,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? initials,
    TResult? Function(String key)? icon,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? initials,
    TResult Function(String key)? icon,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaylistVisualEdit_Keep value) keep,
    required TResult Function(PlaylistVisualEdit_Initials value) initials,
    required TResult Function(PlaylistVisualEdit_Icon value) icon,
    required TResult Function(PlaylistVisualEdit_Image value) image,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaylistVisualEdit_Keep value)? keep,
    TResult? Function(PlaylistVisualEdit_Initials value)? initials,
    TResult? Function(PlaylistVisualEdit_Icon value)? icon,
    TResult? Function(PlaylistVisualEdit_Image value)? image,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaylistVisualEdit_Keep value)? keep,
    TResult Function(PlaylistVisualEdit_Initials value)? initials,
    TResult Function(PlaylistVisualEdit_Icon value)? icon,
    TResult Function(PlaylistVisualEdit_Image value)? image,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaylistVisualEditCopyWith<$Res> {
  factory $PlaylistVisualEditCopyWith(
    PlaylistVisualEdit value,
    $Res Function(PlaylistVisualEdit) then,
  ) = _$PlaylistVisualEditCopyWithImpl<$Res, PlaylistVisualEdit>;
}

/// @nodoc
class _$PlaylistVisualEditCopyWithImpl<$Res, $Val extends PlaylistVisualEdit>
    implements $PlaylistVisualEditCopyWith<$Res> {
  _$PlaylistVisualEditCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$PlaylistVisualEdit_KeepImplCopyWith<$Res> {
  factory _$$PlaylistVisualEdit_KeepImplCopyWith(
    _$PlaylistVisualEdit_KeepImpl value,
    $Res Function(_$PlaylistVisualEdit_KeepImpl) then,
  ) = __$$PlaylistVisualEdit_KeepImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlaylistVisualEdit_KeepImplCopyWithImpl<$Res>
    extends
        _$PlaylistVisualEditCopyWithImpl<$Res, _$PlaylistVisualEdit_KeepImpl>
    implements _$$PlaylistVisualEdit_KeepImplCopyWith<$Res> {
  __$$PlaylistVisualEdit_KeepImplCopyWithImpl(
    _$PlaylistVisualEdit_KeepImpl _value,
    $Res Function(_$PlaylistVisualEdit_KeepImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$PlaylistVisualEdit_KeepImpl extends PlaylistVisualEdit_Keep {
  const _$PlaylistVisualEdit_KeepImpl() : super._();

  @override
  String toString() {
    return 'PlaylistVisualEdit.keep()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistVisualEdit_KeepImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() initials,
    required TResult Function(String key) icon,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    image,
  }) {
    return keep();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? initials,
    TResult? Function(String key)? icon,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
  }) {
    return keep?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? initials,
    TResult Function(String key)? icon,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaylistVisualEdit_Keep value) keep,
    required TResult Function(PlaylistVisualEdit_Initials value) initials,
    required TResult Function(PlaylistVisualEdit_Icon value) icon,
    required TResult Function(PlaylistVisualEdit_Image value) image,
  }) {
    return keep(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaylistVisualEdit_Keep value)? keep,
    TResult? Function(PlaylistVisualEdit_Initials value)? initials,
    TResult? Function(PlaylistVisualEdit_Icon value)? icon,
    TResult? Function(PlaylistVisualEdit_Image value)? image,
  }) {
    return keep?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaylistVisualEdit_Keep value)? keep,
    TResult Function(PlaylistVisualEdit_Initials value)? initials,
    TResult Function(PlaylistVisualEdit_Icon value)? icon,
    TResult Function(PlaylistVisualEdit_Image value)? image,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep(this);
    }
    return orElse();
  }
}

abstract class PlaylistVisualEdit_Keep extends PlaylistVisualEdit {
  const factory PlaylistVisualEdit_Keep() = _$PlaylistVisualEdit_KeepImpl;
  const PlaylistVisualEdit_Keep._() : super._();
}

/// @nodoc
abstract class _$$PlaylistVisualEdit_InitialsImplCopyWith<$Res> {
  factory _$$PlaylistVisualEdit_InitialsImplCopyWith(
    _$PlaylistVisualEdit_InitialsImpl value,
    $Res Function(_$PlaylistVisualEdit_InitialsImpl) then,
  ) = __$$PlaylistVisualEdit_InitialsImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlaylistVisualEdit_InitialsImplCopyWithImpl<$Res>
    extends
        _$PlaylistVisualEditCopyWithImpl<
          $Res,
          _$PlaylistVisualEdit_InitialsImpl
        >
    implements _$$PlaylistVisualEdit_InitialsImplCopyWith<$Res> {
  __$$PlaylistVisualEdit_InitialsImplCopyWithImpl(
    _$PlaylistVisualEdit_InitialsImpl _value,
    $Res Function(_$PlaylistVisualEdit_InitialsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$PlaylistVisualEdit_InitialsImpl extends PlaylistVisualEdit_Initials {
  const _$PlaylistVisualEdit_InitialsImpl() : super._();

  @override
  String toString() {
    return 'PlaylistVisualEdit.initials()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistVisualEdit_InitialsImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() initials,
    required TResult Function(String key) icon,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    image,
  }) {
    return initials();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? initials,
    TResult? Function(String key)? icon,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
  }) {
    return initials?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? initials,
    TResult Function(String key)? icon,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
    required TResult orElse(),
  }) {
    if (initials != null) {
      return initials();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaylistVisualEdit_Keep value) keep,
    required TResult Function(PlaylistVisualEdit_Initials value) initials,
    required TResult Function(PlaylistVisualEdit_Icon value) icon,
    required TResult Function(PlaylistVisualEdit_Image value) image,
  }) {
    return initials(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaylistVisualEdit_Keep value)? keep,
    TResult? Function(PlaylistVisualEdit_Initials value)? initials,
    TResult? Function(PlaylistVisualEdit_Icon value)? icon,
    TResult? Function(PlaylistVisualEdit_Image value)? image,
  }) {
    return initials?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaylistVisualEdit_Keep value)? keep,
    TResult Function(PlaylistVisualEdit_Initials value)? initials,
    TResult Function(PlaylistVisualEdit_Icon value)? icon,
    TResult Function(PlaylistVisualEdit_Image value)? image,
    required TResult orElse(),
  }) {
    if (initials != null) {
      return initials(this);
    }
    return orElse();
  }
}

abstract class PlaylistVisualEdit_Initials extends PlaylistVisualEdit {
  const factory PlaylistVisualEdit_Initials() =
      _$PlaylistVisualEdit_InitialsImpl;
  const PlaylistVisualEdit_Initials._() : super._();
}

/// @nodoc
abstract class _$$PlaylistVisualEdit_IconImplCopyWith<$Res> {
  factory _$$PlaylistVisualEdit_IconImplCopyWith(
    _$PlaylistVisualEdit_IconImpl value,
    $Res Function(_$PlaylistVisualEdit_IconImpl) then,
  ) = __$$PlaylistVisualEdit_IconImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String key});
}

/// @nodoc
class __$$PlaylistVisualEdit_IconImplCopyWithImpl<$Res>
    extends
        _$PlaylistVisualEditCopyWithImpl<$Res, _$PlaylistVisualEdit_IconImpl>
    implements _$$PlaylistVisualEdit_IconImplCopyWith<$Res> {
  __$$PlaylistVisualEdit_IconImplCopyWithImpl(
    _$PlaylistVisualEdit_IconImpl _value,
    $Res Function(_$PlaylistVisualEdit_IconImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? key = null}) {
    return _then(
      _$PlaylistVisualEdit_IconImpl(
        key: null == key
            ? _value.key
            : key // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$PlaylistVisualEdit_IconImpl extends PlaylistVisualEdit_Icon {
  const _$PlaylistVisualEdit_IconImpl({required this.key}) : super._();

  @override
  final String key;

  @override
  String toString() {
    return 'PlaylistVisualEdit.icon(key: $key)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistVisualEdit_IconImpl &&
            (identical(other.key, key) || other.key == key));
  }

  @override
  int get hashCode => Object.hash(runtimeType, key);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaylistVisualEdit_IconImplCopyWith<_$PlaylistVisualEdit_IconImpl>
  get copyWith =>
      __$$PlaylistVisualEdit_IconImplCopyWithImpl<
        _$PlaylistVisualEdit_IconImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() initials,
    required TResult Function(String key) icon,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    image,
  }) {
    return icon(key);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? initials,
    TResult? Function(String key)? icon,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
  }) {
    return icon?.call(key);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? initials,
    TResult Function(String key)? icon,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
    required TResult orElse(),
  }) {
    if (icon != null) {
      return icon(key);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaylistVisualEdit_Keep value) keep,
    required TResult Function(PlaylistVisualEdit_Initials value) initials,
    required TResult Function(PlaylistVisualEdit_Icon value) icon,
    required TResult Function(PlaylistVisualEdit_Image value) image,
  }) {
    return icon(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaylistVisualEdit_Keep value)? keep,
    TResult? Function(PlaylistVisualEdit_Initials value)? initials,
    TResult? Function(PlaylistVisualEdit_Icon value)? icon,
    TResult? Function(PlaylistVisualEdit_Image value)? image,
  }) {
    return icon?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaylistVisualEdit_Keep value)? keep,
    TResult Function(PlaylistVisualEdit_Initials value)? initials,
    TResult Function(PlaylistVisualEdit_Icon value)? icon,
    TResult Function(PlaylistVisualEdit_Image value)? image,
    required TResult orElse(),
  }) {
    if (icon != null) {
      return icon(this);
    }
    return orElse();
  }
}

abstract class PlaylistVisualEdit_Icon extends PlaylistVisualEdit {
  const factory PlaylistVisualEdit_Icon({required final String key}) =
      _$PlaylistVisualEdit_IconImpl;
  const PlaylistVisualEdit_Icon._() : super._();

  String get key;

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaylistVisualEdit_IconImplCopyWith<_$PlaylistVisualEdit_IconImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PlaylistVisualEdit_ImageImplCopyWith<$Res> {
  factory _$$PlaylistVisualEdit_ImageImplCopyWith(
    _$PlaylistVisualEdit_ImageImpl value,
    $Res Function(_$PlaylistVisualEdit_ImageImpl) then,
  ) = __$$PlaylistVisualEdit_ImageImplCopyWithImpl<$Res>;
  @useResult
  $Res call({
    String originalSourcePath,
    String croppedSourcePath,
    ArtworkCropRectData crop,
  });
}

/// @nodoc
class __$$PlaylistVisualEdit_ImageImplCopyWithImpl<$Res>
    extends
        _$PlaylistVisualEditCopyWithImpl<$Res, _$PlaylistVisualEdit_ImageImpl>
    implements _$$PlaylistVisualEdit_ImageImplCopyWith<$Res> {
  __$$PlaylistVisualEdit_ImageImplCopyWithImpl(
    _$PlaylistVisualEdit_ImageImpl _value,
    $Res Function(_$PlaylistVisualEdit_ImageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? originalSourcePath = null,
    Object? croppedSourcePath = null,
    Object? crop = null,
  }) {
    return _then(
      _$PlaylistVisualEdit_ImageImpl(
        originalSourcePath: null == originalSourcePath
            ? _value.originalSourcePath
            : originalSourcePath // ignore: cast_nullable_to_non_nullable
                  as String,
        croppedSourcePath: null == croppedSourcePath
            ? _value.croppedSourcePath
            : croppedSourcePath // ignore: cast_nullable_to_non_nullable
                  as String,
        crop: null == crop
            ? _value.crop
            : crop // ignore: cast_nullable_to_non_nullable
                  as ArtworkCropRectData,
      ),
    );
  }
}

/// @nodoc

class _$PlaylistVisualEdit_ImageImpl extends PlaylistVisualEdit_Image {
  const _$PlaylistVisualEdit_ImageImpl({
    required this.originalSourcePath,
    required this.croppedSourcePath,
    required this.crop,
  }) : super._();

  @override
  final String originalSourcePath;
  @override
  final String croppedSourcePath;
  @override
  final ArtworkCropRectData crop;

  @override
  String toString() {
    return 'PlaylistVisualEdit.image(originalSourcePath: $originalSourcePath, croppedSourcePath: $croppedSourcePath, crop: $crop)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistVisualEdit_ImageImpl &&
            (identical(other.originalSourcePath, originalSourcePath) ||
                other.originalSourcePath == originalSourcePath) &&
            (identical(other.croppedSourcePath, croppedSourcePath) ||
                other.croppedSourcePath == croppedSourcePath) &&
            (identical(other.crop, crop) || other.crop == crop));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, originalSourcePath, croppedSourcePath, crop);

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaylistVisualEdit_ImageImplCopyWith<_$PlaylistVisualEdit_ImageImpl>
  get copyWith =>
      __$$PlaylistVisualEdit_ImageImplCopyWithImpl<
        _$PlaylistVisualEdit_ImageImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function() initials,
    required TResult Function(String key) icon,
    required TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )
    image,
  }) {
    return image(originalSourcePath, croppedSourcePath, crop);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function()? initials,
    TResult? Function(String key)? icon,
    TResult? Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
  }) {
    return image?.call(originalSourcePath, croppedSourcePath, crop);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function()? initials,
    TResult Function(String key)? icon,
    TResult Function(
      String originalSourcePath,
      String croppedSourcePath,
      ArtworkCropRectData crop,
    )?
    image,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(originalSourcePath, croppedSourcePath, crop);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaylistVisualEdit_Keep value) keep,
    required TResult Function(PlaylistVisualEdit_Initials value) initials,
    required TResult Function(PlaylistVisualEdit_Icon value) icon,
    required TResult Function(PlaylistVisualEdit_Image value) image,
  }) {
    return image(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaylistVisualEdit_Keep value)? keep,
    TResult? Function(PlaylistVisualEdit_Initials value)? initials,
    TResult? Function(PlaylistVisualEdit_Icon value)? icon,
    TResult? Function(PlaylistVisualEdit_Image value)? image,
  }) {
    return image?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaylistVisualEdit_Keep value)? keep,
    TResult Function(PlaylistVisualEdit_Initials value)? initials,
    TResult Function(PlaylistVisualEdit_Icon value)? icon,
    TResult Function(PlaylistVisualEdit_Image value)? image,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(this);
    }
    return orElse();
  }
}

abstract class PlaylistVisualEdit_Image extends PlaylistVisualEdit {
  const factory PlaylistVisualEdit_Image({
    required final String originalSourcePath,
    required final String croppedSourcePath,
    required final ArtworkCropRectData crop,
  }) = _$PlaylistVisualEdit_ImageImpl;
  const PlaylistVisualEdit_Image._() : super._();

  String get originalSourcePath;
  String get croppedSourcePath;
  ArtworkCropRectData get crop;

  /// Create a copy of PlaylistVisualEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaylistVisualEdit_ImageImplCopyWith<_$PlaylistVisualEdit_ImageImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SongAudioEdit {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function(String sourcePath, int startMs, int endMs)
    applyCrop,
    required TResult Function() restoreOriginal,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult? Function()? restoreOriginal,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult Function()? restoreOriginal,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SongAudioEdit_Keep value) keep,
    required TResult Function(SongAudioEdit_ApplyCrop value) applyCrop,
    required TResult Function(SongAudioEdit_RestoreOriginal value)
    restoreOriginal,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SongAudioEdit_Keep value)? keep,
    TResult? Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult? Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SongAudioEdit_Keep value)? keep,
    TResult Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SongAudioEditCopyWith<$Res> {
  factory $SongAudioEditCopyWith(
    SongAudioEdit value,
    $Res Function(SongAudioEdit) then,
  ) = _$SongAudioEditCopyWithImpl<$Res, SongAudioEdit>;
}

/// @nodoc
class _$SongAudioEditCopyWithImpl<$Res, $Val extends SongAudioEdit>
    implements $SongAudioEditCopyWith<$Res> {
  _$SongAudioEditCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$SongAudioEdit_KeepImplCopyWith<$Res> {
  factory _$$SongAudioEdit_KeepImplCopyWith(
    _$SongAudioEdit_KeepImpl value,
    $Res Function(_$SongAudioEdit_KeepImpl) then,
  ) = __$$SongAudioEdit_KeepImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$SongAudioEdit_KeepImplCopyWithImpl<$Res>
    extends _$SongAudioEditCopyWithImpl<$Res, _$SongAudioEdit_KeepImpl>
    implements _$$SongAudioEdit_KeepImplCopyWith<$Res> {
  __$$SongAudioEdit_KeepImplCopyWithImpl(
    _$SongAudioEdit_KeepImpl _value,
    $Res Function(_$SongAudioEdit_KeepImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$SongAudioEdit_KeepImpl extends SongAudioEdit_Keep {
  const _$SongAudioEdit_KeepImpl() : super._();

  @override
  String toString() {
    return 'SongAudioEdit.keep()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$SongAudioEdit_KeepImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function(String sourcePath, int startMs, int endMs)
    applyCrop,
    required TResult Function() restoreOriginal,
  }) {
    return keep();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult? Function()? restoreOriginal,
  }) {
    return keep?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult Function()? restoreOriginal,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SongAudioEdit_Keep value) keep,
    required TResult Function(SongAudioEdit_ApplyCrop value) applyCrop,
    required TResult Function(SongAudioEdit_RestoreOriginal value)
    restoreOriginal,
  }) {
    return keep(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SongAudioEdit_Keep value)? keep,
    TResult? Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult? Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
  }) {
    return keep?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SongAudioEdit_Keep value)? keep,
    TResult Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
    required TResult orElse(),
  }) {
    if (keep != null) {
      return keep(this);
    }
    return orElse();
  }
}

abstract class SongAudioEdit_Keep extends SongAudioEdit {
  const factory SongAudioEdit_Keep() = _$SongAudioEdit_KeepImpl;
  const SongAudioEdit_Keep._() : super._();
}

/// @nodoc
abstract class _$$SongAudioEdit_ApplyCropImplCopyWith<$Res> {
  factory _$$SongAudioEdit_ApplyCropImplCopyWith(
    _$SongAudioEdit_ApplyCropImpl value,
    $Res Function(_$SongAudioEdit_ApplyCropImpl) then,
  ) = __$$SongAudioEdit_ApplyCropImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String sourcePath, int startMs, int endMs});
}

/// @nodoc
class __$$SongAudioEdit_ApplyCropImplCopyWithImpl<$Res>
    extends _$SongAudioEditCopyWithImpl<$Res, _$SongAudioEdit_ApplyCropImpl>
    implements _$$SongAudioEdit_ApplyCropImplCopyWith<$Res> {
  __$$SongAudioEdit_ApplyCropImplCopyWithImpl(
    _$SongAudioEdit_ApplyCropImpl _value,
    $Res Function(_$SongAudioEdit_ApplyCropImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sourcePath = null,
    Object? startMs = null,
    Object? endMs = null,
  }) {
    return _then(
      _$SongAudioEdit_ApplyCropImpl(
        sourcePath: null == sourcePath
            ? _value.sourcePath
            : sourcePath // ignore: cast_nullable_to_non_nullable
                  as String,
        startMs: null == startMs
            ? _value.startMs
            : startMs // ignore: cast_nullable_to_non_nullable
                  as int,
        endMs: null == endMs
            ? _value.endMs
            : endMs // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc

class _$SongAudioEdit_ApplyCropImpl extends SongAudioEdit_ApplyCrop {
  const _$SongAudioEdit_ApplyCropImpl({
    required this.sourcePath,
    required this.startMs,
    required this.endMs,
  }) : super._();

  @override
  final String sourcePath;
  @override
  final int startMs;
  @override
  final int endMs;

  @override
  String toString() {
    return 'SongAudioEdit.applyCrop(sourcePath: $sourcePath, startMs: $startMs, endMs: $endMs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SongAudioEdit_ApplyCropImpl &&
            (identical(other.sourcePath, sourcePath) ||
                other.sourcePath == sourcePath) &&
            (identical(other.startMs, startMs) || other.startMs == startMs) &&
            (identical(other.endMs, endMs) || other.endMs == endMs));
  }

  @override
  int get hashCode => Object.hash(runtimeType, sourcePath, startMs, endMs);

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SongAudioEdit_ApplyCropImplCopyWith<_$SongAudioEdit_ApplyCropImpl>
  get copyWith =>
      __$$SongAudioEdit_ApplyCropImplCopyWithImpl<
        _$SongAudioEdit_ApplyCropImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function(String sourcePath, int startMs, int endMs)
    applyCrop,
    required TResult Function() restoreOriginal,
  }) {
    return applyCrop(sourcePath, startMs, endMs);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult? Function()? restoreOriginal,
  }) {
    return applyCrop?.call(sourcePath, startMs, endMs);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult Function()? restoreOriginal,
    required TResult orElse(),
  }) {
    if (applyCrop != null) {
      return applyCrop(sourcePath, startMs, endMs);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SongAudioEdit_Keep value) keep,
    required TResult Function(SongAudioEdit_ApplyCrop value) applyCrop,
    required TResult Function(SongAudioEdit_RestoreOriginal value)
    restoreOriginal,
  }) {
    return applyCrop(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SongAudioEdit_Keep value)? keep,
    TResult? Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult? Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
  }) {
    return applyCrop?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SongAudioEdit_Keep value)? keep,
    TResult Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
    required TResult orElse(),
  }) {
    if (applyCrop != null) {
      return applyCrop(this);
    }
    return orElse();
  }
}

abstract class SongAudioEdit_ApplyCrop extends SongAudioEdit {
  const factory SongAudioEdit_ApplyCrop({
    required final String sourcePath,
    required final int startMs,
    required final int endMs,
  }) = _$SongAudioEdit_ApplyCropImpl;
  const SongAudioEdit_ApplyCrop._() : super._();

  String get sourcePath;
  int get startMs;
  int get endMs;

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SongAudioEdit_ApplyCropImplCopyWith<_$SongAudioEdit_ApplyCropImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SongAudioEdit_RestoreOriginalImplCopyWith<$Res> {
  factory _$$SongAudioEdit_RestoreOriginalImplCopyWith(
    _$SongAudioEdit_RestoreOriginalImpl value,
    $Res Function(_$SongAudioEdit_RestoreOriginalImpl) then,
  ) = __$$SongAudioEdit_RestoreOriginalImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$SongAudioEdit_RestoreOriginalImplCopyWithImpl<$Res>
    extends
        _$SongAudioEditCopyWithImpl<$Res, _$SongAudioEdit_RestoreOriginalImpl>
    implements _$$SongAudioEdit_RestoreOriginalImplCopyWith<$Res> {
  __$$SongAudioEdit_RestoreOriginalImplCopyWithImpl(
    _$SongAudioEdit_RestoreOriginalImpl _value,
    $Res Function(_$SongAudioEdit_RestoreOriginalImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SongAudioEdit
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$SongAudioEdit_RestoreOriginalImpl
    extends SongAudioEdit_RestoreOriginal {
  const _$SongAudioEdit_RestoreOriginalImpl() : super._();

  @override
  String toString() {
    return 'SongAudioEdit.restoreOriginal()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SongAudioEdit_RestoreOriginalImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() keep,
    required TResult Function(String sourcePath, int startMs, int endMs)
    applyCrop,
    required TResult Function() restoreOriginal,
  }) {
    return restoreOriginal();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? keep,
    TResult? Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult? Function()? restoreOriginal,
  }) {
    return restoreOriginal?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? keep,
    TResult Function(String sourcePath, int startMs, int endMs)? applyCrop,
    TResult Function()? restoreOriginal,
    required TResult orElse(),
  }) {
    if (restoreOriginal != null) {
      return restoreOriginal();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SongAudioEdit_Keep value) keep,
    required TResult Function(SongAudioEdit_ApplyCrop value) applyCrop,
    required TResult Function(SongAudioEdit_RestoreOriginal value)
    restoreOriginal,
  }) {
    return restoreOriginal(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SongAudioEdit_Keep value)? keep,
    TResult? Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult? Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
  }) {
    return restoreOriginal?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SongAudioEdit_Keep value)? keep,
    TResult Function(SongAudioEdit_ApplyCrop value)? applyCrop,
    TResult Function(SongAudioEdit_RestoreOriginal value)? restoreOriginal,
    required TResult orElse(),
  }) {
    if (restoreOriginal != null) {
      return restoreOriginal(this);
    }
    return orElse();
  }
}

abstract class SongAudioEdit_RestoreOriginal extends SongAudioEdit {
  const factory SongAudioEdit_RestoreOriginal() =
      _$SongAudioEdit_RestoreOriginalImpl;
  const SongAudioEdit_RestoreOriginal._() : super._();
}
