create_sandbox_tag () {
	local label constraints_hash \
		ghc_version ghc_magic_hash \
		sandbox_magic_hash
	expect_args label constraints_hash \
		ghc_version ghc_magic_hash \
		sandbox_magic_hash -- "$@"

	create_tag '' "${label}" '' "${constraints_hash}" '' \
		"${ghc_version}" "${ghc_magic_hash}" \
		'' '' '' '' \
		"${sandbox_magic_hash}" || die
}


detect_sandbox_tag () {
	local tag_file
	expect_args tag_file -- "$@"

	local tag_pattern
	tag_pattern=$( create_sandbox_tag '.*' '.*' '.*' '.*' '.*' ) || die

	local tag
	if ! tag=$( detect_tag "${tag_file}" "${tag_pattern}" ); then
		die 'Failed to detect sandbox layer tag'
	fi

	echo "${tag}"
}


derive_sandbox_tag () {
	local tag
	expect_args tag -- "$@"

	local label constraints_hash ghc_version ghc_magic_hash sandbox_magic_hash
	label=$( get_tag_label "${tag}" ) || die
	constraints_hash=$( get_tag_constraints_hash "${tag}" ) || die
	ghc_version=$( get_tag_ghc_version "${tag}" ) || die
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" ) || die
	sandbox_magic_hash=$( get_tag_sandbox_magic_hash "${tag}" ) || die

	create_sandbox_tag "${label}" "${constraints_hash}" \
		"${ghc_version}" "${ghc_magic_hash}" \
		"${sandbox_magic_hash}" || die
}


derive_matching_sandbox_tag () {
	local tag label constraints_hash
	expect_args tag label constraints_hash -- "$@"

	local ghc_version ghc_magic_hash sandbox_magic_hash
	ghc_version=$( get_tag_ghc_version "${tag}" ) || die
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" ) || die
	sandbox_magic_hash=$( get_tag_sandbox_magic_hash "${tag}" ) || die

	create_sandbox_tag "${label}" "${constraints_hash}" \
		"${ghc_version}" "${ghc_magic_hash}" \
		"${sandbox_magic_hash}" || die
}


format_sandbox_id () {
	local tag
	expect_args tag -- "$@"

	local constraints_hash sandbox_magic_hash
	constraints_hash=$( get_tag_constraints_hash "${tag}" ) || die
	sandbox_magic_hash=$( get_tag_sandbox_magic_hash "${tag}" ) || die

	echo "${constraints_hash:0:7}${sandbox_magic_hash:+.${sandbox_magic_hash:0:7}}"
}


format_sandbox_description () {
	local tag
	expect_args tag -- "$@"

	local label sandbox_id
	label=$( get_tag_label "${tag}" ) || die
	sandbox_id=$( format_sandbox_id "${tag}" ) || die

	echo "${label} (${sandbox_id})"
}


format_sandbox_archive_name () {
	local tag
	expect_args tag -- "$@"

	local label sandbox_id
	label=$( get_tag_label "${tag}" ) || die
	sandbox_id=$( format_sandbox_id "${tag}" ) || die

	echo "halcyon-sandbox-${sandbox_id}-${label}.tar.gz"
}


format_sandbox_constraints_file_name () {
	local tag
	expect_args tag -- "$@"

	local label sandbox_id
	label=$( get_tag_label "${tag}" ) || die
	sandbox_id=$( format_sandbox_id "${tag}" ) || die

	echo "halcyon-sandbox-${sandbox_id}-${label}.constraints"
}


format_full_sandbox_constraints_file_name_pattern () {
	local tag
	expect_args tag -- "$@"

	local sandbox_id
	sandbox_id=$( format_sandbox_id "${tag}" ) || die

	echo "halcyon-sandbox-${sandbox_id}-.*.constraints"
}


format_partial_sandbox_constraints_file_name_pattern () {
	local tag
	expect_args tag -- "$@"

	local sandbox_magic_hash
	sandbox_magic_hash=$( get_tag_sandbox_magic_hash "${tag}" ) || die

	echo "halcyon-sandbox-.*${sandbox_magic_hash:+.${sandbox_magic_hash:0:7}}-.*.constraints"
}


format_sandbox_common_file_name_prefix () {
	echo "halcyon-sandbox-"
}


format_sandbox_common_file_name_pattern () {
	local tag
	expect_args tag -- "$@"

	local label
	label=$( get_tag_label "${tag}" ) || die

	echo "halcyon-sandbox-.*-${label}.(tar.gz|constraints)"
}


map_sandbox_constraints_file_name_to_label () {
	local constraints_name
	expect_args constraints_name -- "$@"

	local label_etc
	label_etc="${constraints_name#halcyon-sandbox-*-}"

	echo "${label_etc%.constraints}"
}


hash_sandbox_magic () {
	local source_dir
	expect_args source_dir -- "$@"

	hash_tree "${source_dir}/.halcyon" \( -path './ghc*' -or -path './sandbox*' \) || die
}


copy_sandbox_magic () {
	expect_vars HALCYON_BASE

	local source_dir
	expect_args source_dir -- "$@"
	expect_existing "${HALCYON_BASE}/sandbox"

	local sandbox_magic_hash
	sandbox_magic_hash=$( hash_sandbox_magic "${source_dir}" ) || die
	if [[ -z "${sandbox_magic_hash}" ]]; then
		return 0
	fi

	local file
	find_tree "${source_dir}/.halcyon" -type f \( -path './ghc*' -or -path './sandbox*' \) |
		while read -r file; do
			copy_file "${source_dir}/.halcyon/${file}" \
				"${HALCYON_BASE}/sandbox/.halcyon/${file}" || die
		done || die
}


add_sandbox_sources () {
	expect_vars HALCYON_BASE

	local source_dir
	expect_args source_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/sandbox-sources" ]]; then
		return 0
	fi

	local sandbox_sources
	sandbox_sources=$( <"${source_dir}/.halcyon/sandbox-sources" ) || die
	if [[ -z "${sandbox_sources}" ]]; then
		return 0
	fi

	local sources_dir
	sources_dir="${HALCYON_BASE}/sandbox/.halcyon-sandbox-sources"

	local all_names
	if ! all_names=$( git_all_over_here "${source_dir}" "${sandbox_sources}" "${sources_dir}" ); then
		die 'Failed to add sandbox sources'
	fi

	local -a names
	names=( ${all_names} )
	if [[ -z "${names[@]:+_}" ]]; then
		return 0
	fi

	local name
	for name in "${names[@]}"; do
		log "Adding sandbox source: ${name}"

		sandboxed_cabal_do "${source_dir}" sandbox add-source "${sources_dir}/${name}" || die
	done
}


install_sandbox_extra_os_packages () {
	expect_vars HALCYON_BASE

	local tag source_dir
	expect_args tag source_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/sandbox-extra-os-packages" ]]; then
		return 0
	fi

	local extra_packages
	extra_packages=$( <"${source_dir}/.halcyon/sandbox-extra-os-packages" ) || die

	log 'Installing sandbox extra OS packages'

	if ! install_platform_packages "${extra_packages}" "${HALCYON_BASE}/sandbox"; then
		die 'Failed to install sandbox extra OS packages'
	fi
}


install_sandbox_extra_apps () {
	expect_vars HALCYON_BASE

	local tag source_dir
	expect_args tag source_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/sandbox-extra-apps" ]]; then
		return 0
	fi

	local -a extra_apps
	extra_apps=( $( <"${source_dir}/.halcyon/sandbox-extra-apps" ) ) || die
	if [[ -z "${extra_apps[@]:+_}" ]]; then
		return 0
	fi

	local ghc_version ghc_magic_hash
	ghc_version=$( get_tag_ghc_version "${tag}" ) || die
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" ) || die

	local cabal_version cabal_magic_hash cabal_repo
	cabal_version=$( get_tag_cabal_version "${tag}" ) || die
	cabal_magic_hash=$( get_tag_cabal_magic_hash "${tag}" ) || die
	cabal_repo=$( get_tag_cabal_repo "${tag}" ) || die

	local extra_constraints
	extra_constraints="${source_dir}/.halcyon/sandbox-extra-apps-constraints"

	local -a opts
	opts=()
	opts+=( --root='/' )
	opts+=( --prefix="${HALCYON_BASE}/sandbox" )
	opts+=( --ghc-version="${ghc_version}" )
	opts+=( --cabal-version="${cabal_version}" )
	opts+=( --cabal-repo="${cabal_repo}" )
	[[ -e "${extra_constraints}" ]] && opts+=( --constraints="${extra_constraints}" )

	log 'Installing sandbox extra apps'

	local extra_app index
	index=0
	for extra_app in "${extra_apps[@]}"; do
		local thing
		if [[ -d "${source_dir}/${extra_app}" ]]; then
			thing="${source_dir}/${extra_app}"
		else
			thing="${extra_app}"
		fi

		index=$(( index + 1 ))
		if (( index > 1 )); then
			log
			log
		fi
		HALCYON_INTERNAL_RECURSIVE=1 \
		HALCYON_INTERNAL_GHC_MAGIC_HASH="${ghc_magic_hash}" \
		HALCYON_INTERNAL_CABAL_MAGIC_HASH="${cabal_magic_hash}" \
		HALCYON_INTERNAL_NO_COPY_LOCAL_SOURCE=1 \
			halcyon install "${opts[@]}" "${thing}" 2>&1 | quote || return 1
	done
}


build_sandbox_layer () {
	expect_vars HALCYON_BASE

	local tag source_dir constraints must_create
	expect_args tag source_dir constraints must_create -- "$@"

	if (( must_create )); then
		rm -rf "${HALCYON_BASE}/sandbox" || die
	else
		expect_existing "${HALCYON_BASE}/sandbox/.halcyon-tag" \
			"${HALCYON_BASE}/sandbox/.halcyon-constraints"
	fi
	expect_existing "${source_dir}"

	log 'Building sandbox layer'

	if (( must_create )); then
		log 'Creating sandbox'

		if ! cabal_create_sandbox; then
			die 'Failed to create sandbox'
		fi
	fi

	add_sandbox_sources "${source_dir}" || die

	# NOTE: Listing executable-only packages in build-tools causes Cabal to expect the
	# executables to be installed, but not to install the packages.
	# https://github.com/haskell/cabal/issues/220

	# NOTE: Listing executable-only packages in build-depends causes Cabal to install the
	# packages, and to fail to recognise the packages have been installed.
	# https://github.com/haskell/cabal/issues/779

	if ! install_sandbox_extra_apps "${tag}" "${source_dir}"; then
		log_warning 'Cannot install sandbox extra apps'
		return 1
	fi

	install_sandbox_extra_os_packages "${tag}" "${source_dir}" || die

	if [[ -f "${source_dir}/.halcyon/sandbox-pre-build-hook" ]]; then
		log 'Executing sandbox pre-build hook'
		if ! (
			HALCYON_INTERNAL_RECURSIVE=1 \
				"${source_dir}/.halcyon/sandbox-pre-build-hook" \
					"${tag}" "${source_dir}" "${constraints}" 2>&1 | quote
		); then
			die 'Failed to execute sandbox pre-build hook'
		fi
		log 'Sandbox pre-build hook executed'
	fi

	log 'Building sandbox'

	local -a opts
	opts=()
	if [[ -f "${source_dir}/.halcyon/sandbox-extra-configure-flags" ]]; then
		local -a raw_opts
		raw_opts=( $( <"${source_dir}/.halcyon/sandbox-extra-configure-flags" ) ) || die
		opts=( $( IFS=$'\n' && echo "${raw_opts[*]:-}" | filter_not_matching '^--prefix' ) )
	fi
	opts+=( --dependencies-only )
	opts+=( --extra-include-dirs="${HALCYON_BASE}/sandbox/usr/include" )
	opts+=( --extra-lib-dirs="${HALCYON_BASE}/sandbox/usr/lib" )

	if ! sandboxed_cabal_do "${source_dir}" install "${opts[@]}" 2>&1 | quote; then
		die 'Failed to build sandbox'
	fi

	format_constraints <<<"${constraints}" >"${HALCYON_BASE}/sandbox/.halcyon-constraints" || die
	copy_sandbox_magic "${source_dir}" || die

	local built_size
	built_size=$( get_size "${HALCYON_BASE}/sandbox" ) || die
	log "Sandbox built, ${built_size}"

	if [[ -f "${source_dir}/.halcyon/sandbox-post-build-hook" ]]; then
		log 'Executing sandbox post-build hook'
		if ! (
			HALCYON_INTERNAL_RECURSIVE=1 \
				"${source_dir}/.halcyon/sandbox-post-build-hook" \
					"${tag}" "${source_dir}" "${constraints}" 2>&1 | quote
		); then
			die 'Failed to execute sandbox post-build hook'
		fi
		log 'Sandbox post-build hook executed'
	fi

	if [[ -d "${HALCYON_BASE}/sandbox/logs" || -d "${HALCYON_BASE}/sandbox/share/doc" ]]; then
		log_indent_begin 'Removing documentation from sandbox layer...'

		rm -rf "${HALCYON_BASE}/sandbox/logs" "${HALCYON_BASE}/sandbox/share/doc" || die

		local trimmed_size
		trimmed_size=$( get_size "${HALCYON_BASE}/sandbox" ) || die
		log_indent_end "done, ${trimmed_size}"
	fi

	log_indent_begin 'Stripping sandbox layer...'

	strip_tree "${HALCYON_BASE}/sandbox" || die

	local stripped_size
	stripped_size=$( get_size "${HALCYON_BASE}/sandbox" ) || die
	log_indent_end "done, ${stripped_size}"

	derive_sandbox_tag "${tag}" >"${HALCYON_BASE}/sandbox/.halcyon-tag" || die
}


archive_sandbox_layer () {
	expect_vars HALCYON_BASE HALCYON_CACHE HALCYON_NO_ARCHIVE HALCYON_NO_CLEAN_PRIVATE_STORAGE
	expect_existing "${HALCYON_BASE}/sandbox/.halcyon-tag" \
		"${HALCYON_BASE}/sandbox/.halcyon-constraints"

	if (( HALCYON_NO_ARCHIVE )); then
		return 0
	fi

	local sandbox_tag platform ghc_version archive_name constraints_name
	sandbox_tag=$( detect_sandbox_tag "${HALCYON_BASE}/sandbox/.halcyon-tag" ) || die
	platform=$( get_tag_platform "${sandbox_tag}" ) || die
	ghc_version=$( get_tag_ghc_version "${sandbox_tag}" ) || die
	archive_name=$( format_sandbox_archive_name "${sandbox_tag}" ) || die
	constraints_name=$( format_sandbox_constraints_file_name "${sandbox_tag}" ) || die

	log 'Archiving sandbox layer'

	create_cached_archive "${HALCYON_BASE}/sandbox" "${archive_name}" || die
	copy_file "${HALCYON_BASE}/sandbox/.halcyon-constraints" \
		"${HALCYON_CACHE}/${constraints_name}" || die

	local no_clean
	no_clean=0
	if ! upload_cached_file "${platform}/ghc-${ghc_version}" "${archive_name}"; then
		no_clean=1
	fi
	if ! upload_cached_file "${platform}/ghc-${ghc_version}" "${constraints_name}"; then
		no_clean=1
	fi
	if (( HALCYON_NO_CLEAN_PRIVATE_STORAGE )) || (( no_clean )); then
		return 0
	fi

	local common_prefix common_pattern
	common_prefix=$( format_sandbox_common_file_name_prefix ) || die
	common_pattern=$( format_sandbox_common_file_name_pattern "${sandbox_tag}" ) || die

	delete_matching_private_stored_files "${platform}/ghc-${ghc_version}" "${common_prefix}" "${common_pattern}" "(${archive_name}|${constraints_name})" || die
}


validate_sandbox_layer () {
	expect_vars HALCYON_BASE

	local tag
	expect_args tag -- "$@"

	local sandbox_tag
	sandbox_tag=$( derive_sandbox_tag "${tag}" ) || die
	detect_tag "${HALCYON_BASE}/sandbox/.halcyon-tag" "${sandbox_tag//./\.}" || return 1
}


restore_sandbox_layer () {
	expect_vars HALCYON_BASE

	local tag
	expect_args tag -- "$@"

	local platform ghc_version archive_name
	platform=$( get_tag_platform "${tag}" ) || die
	ghc_version=$( get_tag_ghc_version "${tag}" ) || die
	archive_name=$( format_sandbox_archive_name "${tag}" ) || die

	if validate_sandbox_layer "${tag}" >'/dev/null'; then
		log 'Using existing sandbox layer'

		touch_cached_file "${archive_name}" || die
		return 0
	fi

	log 'Restoring sandbox layer'

	if ! extract_cached_archive_over "${archive_name}" "${HALCYON_BASE}/sandbox" ||
		! validate_sandbox_layer "${tag}" >'/dev/null'
	then
		if ! cache_stored_file "${platform}/ghc-${ghc_version}" "${archive_name}" ||
			! extract_cached_archive_over "${archive_name}" "${HALCYON_BASE}/sandbox" ||
			! validate_sandbox_layer "${tag}" >'/dev/null'
		then
			return 1
		fi
	else
		touch_cached_file "${archive_name}" || die
	fi
}


get_sandbox_package_db () {
	expect_vars HALCYON_BASE

	filter_matching '^package-db: ' <"${HALCYON_BASE}/sandbox/.halcyon-sandbox.config" |
		match_exactly_one |
		awk '{ print $2 }' || return 1
}


recache_sandbox_package_db () {
	local package_db
	package_db=$( get_sandbox_package_db ) || die

	ghc-pkg recache --package-db="${package_db}" 2>&1 | quote || die
}


install_matching_sandbox_layer () {
	expect_vars HALCYON_BASE

	local tag source_dir constraints matching_tag
	expect_args tag source_dir constraints matching_tag -- "$@"

	local constraints_hash matching_hash matching_description
	constraints_hash=$( get_tag_constraints_hash "${tag}" ) || die
	matching_hash=$( get_tag_constraints_hash "${matching_tag}" ) || die
	matching_description=$( format_sandbox_description "${matching_tag}" ) || die

	if [[ "${matching_hash}" == "${constraints_hash}" ]]; then
		log_label 'Using fully matching sandbox layer:' "${matching_description}"

		restore_sandbox_layer "${matching_tag}" || return 1
		recache_sandbox_package_db || die

		derive_sandbox_tag "${tag}" >"${HALCYON_BASE}/sandbox/.halcyon-tag" || die
		return 0
	fi

	log_label 'Using partially matching sandbox layer:' "${matching_description}"

	restore_sandbox_layer "${matching_tag}" || return 1
	recache_sandbox_package_db || die

	local must_create
	must_create=0
	build_sandbox_layer "${tag}" "${source_dir}" "${constraints}" "${must_create}" || return 1
}


install_sandbox_layer () {
	expect_vars HALCYON_NO_BUILD HALCYON_NO_BUILD_LAYERS \
		HALCYON_SANDBOX_REBUILD

	local tag source_dir constraints
	expect_args tag source_dir constraints -- "$@"

	if ! (( HALCYON_SANDBOX_REBUILD )); then
		if restore_sandbox_layer "${tag}"; then
			recache_sandbox_package_db || die
			return 0
		fi

		local matching_tag
		if matching_tag=$( match_sandbox_layer "${tag}" "${constraints}" ) &&
			install_matching_sandbox_layer "${tag}" "${source_dir}" "${constraints}" "${matching_tag}"
		then
			archive_sandbox_layer || die
			return 0
		fi

		if (( HALCYON_NO_BUILD )) || (( HALCYON_NO_BUILD_LAYERS )); then
			log_warning 'Cannot build sandbox layer'
			return 1
		fi
	fi

	local must_create
	must_create=1
	if ! build_sandbox_layer "${tag}" "${source_dir}" "${constraints}" "${must_create}"; then
		log_warning 'Cannot build sandbox layer'
		return 1
	fi
	archive_sandbox_layer || die
}
