create_install_tag () {
	local prefix label source_hash
	expect_args prefix label source_hash -- "$@"

	create_tag "${prefix}" "${label}" "${source_hash}" '' '' \
		'' '' \
		'' '' '' '' \
		'' || die
}


detect_install_tag () {
	local tag_file
	expect_args tag_file -- "$@"

	local tag_pattern
	tag_pattern=$( create_install_tag '.*' '.*' '.*' ) || die

	local tag
	if ! tag=$( detect_tag "${tag_file}" "${tag_pattern}" ); then
		die 'Failed to detect install tag'
	fi

	echo "${tag}"
}


derive_install_tag () {
	local tag
	expect_args tag -- "$@"

	local prefix label source_hash
	prefix=$( get_tag_prefix "${tag}" ) || die
	label=$( get_tag_label "${tag}" ) || die
	source_hash=$( get_tag_source_hash "${tag}" ) || die

	create_install_tag "${prefix}" "${label}" "${source_hash}" || die
}


format_install_id () {
	local tag
	expect_args tag -- "$@"

	local label source_hash
	label=$( get_tag_label "${tag}" ) || die
	source_hash=$( get_tag_source_hash "${tag}" ) || die

	echo "${source_hash:0:7}-${label}"
}


format_install_archive_name () {
	local tag
	expect_args tag -- "$@"

	local install_id
	install_id=$( format_install_id "${tag}" ) || die

	echo "halcyon-install-${install_id}.tar.gz"
}


format_install_archive_name_prefix () {
	echo 'halcyon-install-'
}


format_install_archive_name_pattern () {
	local tag
	expect_args tag -- "$@"

	local label
	label=$( get_tag_label "${tag}" ) || die

	echo "halcyon-install-.*-${label//./\.}.tar.gz"
}


install_extra_apps () {
	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/extra-apps" ]]; then
		return 0
	fi

	local -a extra_apps
	extra_apps=( $( <"${source_dir}/.halcyon/extra-apps" ) ) || die
	if [[ -z "${extra_apps[@]:+_}" ]]; then
		return 0
	fi

	local prefix
	prefix=$( get_tag_prefix "${tag}" ) || die

	local ghc_version ghc_magic_hash
	ghc_version=$( get_tag_ghc_version "${tag}" ) || die
	ghc_magic_hash=$( get_tag_ghc_magic_hash "${tag}" ) || die

	local cabal_version cabal_magic_hash cabal_repo
	cabal_version=$( get_tag_cabal_version "${tag}" ) || die
	cabal_magic_hash=$( get_tag_cabal_magic_hash "${tag}" ) || die
	cabal_repo=$( get_tag_cabal_repo "${tag}" ) || die

	local extra_constraints
	extra_constraints="${source_dir}/.halcyon/extra-apps-constraints"

	local -a opts
	opts=()
	opts+=( --prefix="${prefix}" )
	opts+=( --root="${install_dir}" )
	opts+=( --ghc-version="${ghc_version}" )
	opts+=( --cabal-version="${cabal_version}" )
	opts+=( --cabal-repo="${cabal_repo}" )
	[[ -e "${extra_constraints}" ]] && opts+=( --constraints="${extra_constraints}" )

	log 'Installing extra apps'

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


install_extra_data_files () {
	expect_vars HALCYON_BASE

	local tag source_dir build_dir install_dir
	expect_args tag source_dir build_dir install_dir -- "$@"
	expect_existing "${build_dir}/dist/.halcyon-data-dir"

	if [[ ! -f "${source_dir}/.halcyon/extra-data-files" ]]; then
		return 0
	fi

	local extra_files data_dir
	extra_files=$( <"${source_dir}/.halcyon/extra-data-files" ) || die
	data_dir=$( <"${build_dir}/dist/.halcyon-data-dir" ) || die

	# NOTE: Extra data files may be directories, and are actually bash globs.

	log_indent 'Including extra data files'

	local glob
	while read -r glob; do
		(
			cd "${build_dir}"
			IFS=''

			local -a files
			files=( ${glob} )
			if [[ -z "${files[@]:+_}" ]]; then
				return 0
			fi

			local file
			for file in "${files[@]}"; do
				if [[ ! -e "${file}" ]]; then
					continue
				fi
				dir=$( dirname "${install_dir}${data_dir}/${file}" ) || die
				mkdir -p "${dir}" || die
				cp -Rp "${file}" "${install_dir}${data_dir}/${file}" || die
			done
		) || die
	done <<<"${extra_files}"
}


install_extra_os_packages () {
	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	if [[ ! -f "${source_dir}/.halcyon/extra-os-packages" ]]; then
		return 0
	fi

	local prefix extra_packages
	prefix=$( get_tag_prefix "${tag}" ) || die
	extra_packages=$( <"${source_dir}/.halcyon/extra-os-packages" ) || die

	log 'Installing extra OS packages'

	if ! install_platform_packages "${extra_packages}" "${install_dir}${prefix}"; then
		die 'Failed to install extra OS packages'
	fi
}


install_extra_layers () {
	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	# NOTE: Cabal libraries may require data files at run-time.
	# See filestore for an example.
	# https://haskell.org/cabal/users-guide/developing-packages.html#accessing-data-files-from-package-code

	if find_tree "${HALCYON_BASE}/sandbox/share" -type f |
		match_at_least_one >'/dev/null'
	then
		copy_dir_into "${HALCYON_BASE}/sandbox/share" "${install_dir}${HALCYON_BASE}/sandbox/share" || die
	fi

	if [[ ! -f "${source_dir}/.halcyon/extra-layers" ]]; then
		return 0
	fi

	log_indent 'Including extra layers'

	local extra_layers
	extra_layers=$( <"${source_dir}/.halcyon/extra-layers" ) || die

	local layer
	while read -r layer; do
		case "${layer}" in
		'ghc')
			copy_dir_into "${HALCYON_BASE}/ghc" "${install_dir}${HALCYON_BASE}/ghc" || die
			;;
		'cabal')
			copy_dir_into "${HALCYON_BASE}/cabal" "${install_dir}${HALCYON_BASE}/cabal" || die
			;;
		'sandbox')
			copy_dir_into "${HALCYON_BASE}/sandbox" "${install_dir}${HALCYON_BASE}/sandbox" || die
			;;
		*)
			die "Unexpected extra layer: ${layer}"
		esac
	done <<<"${extra_layers}"
}


prepare_install_dir () {
	expect_vars HALCYON_BASE

	local tag source_dir constraints build_dir install_dir
	expect_args tag source_dir constraints build_dir install_dir -- "$@"
	expect_existing "${build_dir}/.halcyon-tag" "${build_dir}/dist/.halcyon-data-dir"

	local prefix label install_id label_dir data_dir
	prefix=$( get_tag_prefix "${tag}" ) || die
	label=$( get_tag_label "${tag}" ) || die
	label_dir="${install_dir}${prefix}/.halcyon/${label}"
	data_dir=$( <"${build_dir}/dist/.halcyon-data-dir" ) || die

	log 'Preparing install'

	# NOTE: PATH is extended to silence a misleading Cabal warning.

	if ! (
		PATH="${install_dir}${prefix}:${PATH}" \
			sandboxed_cabal_do "${build_dir}" copy \
				--destdir="${install_dir}" --verbose=0 2>&1 | quote
	); then
		die 'Failed to copy app'
	fi

	mkdir -p "${label_dir}" || die
	sandboxed_cabal_do "${build_dir}" register \
		--gen-pkg-config="${label_dir}/${label}.conf" --verbose=0 2>&1 | quote || die

	ln -s "${HALCYON_BASE}/sandbox/.halcyon-sandbox.config" "${install_dir}${prefix}/cabal.sandbox.config" || die

	format_constraints <<<"${constraints}" >"${label_dir}/constraints" || die
	echo "${data_dir}" >"${label_dir}/data-dir" || die

	local executable
	if executable=$( detect_executable "${source_dir}" ); then
		echo "${executable}" >"${label_dir}/executable" || die
	fi

	derive_install_tag "${tag}" >"${label_dir}/tag" || die

	if ! install_extra_apps "${tag}" "${source_dir}" "${install_dir}"; then
		log_warning 'Cannot install extra apps'
		return 1
	fi

	install_extra_data_files "${tag}" "${source_dir}" "${build_dir}" "${install_dir}" || die
	install_extra_os_packages "${tag}" "${source_dir}" "${install_dir}" || die
	install_extra_layers "${tag}" "${source_dir}" "${install_dir}" || die

	if [[ -f "${source_dir}/.halcyon/pre-install-hook" ]]; then
		log 'Executing pre-install hook'
		if ! (
			HALCYON_INTERNAL_RECURSIVE=1 \
				"${source_dir}/.halcyon/pre-install-hook" \
					"${tag}" "${source_dir}" "${install_dir}" "${data_dir}" 2>&1 | quote
		); then
			die 'Failed to execute pre-install hook'
		fi
		log 'Pre-install hook executed'
	fi

	local prepared_size
	prepared_size=$( get_size "${install_dir}" ) || die
	log "Install prepared, ${prepared_size}"

	if [[ -d "${install_dir}${prefix}/share/doc" ]]; then
		log_indent_begin 'Removing documentation from install...'

		rm -rf "${install_dir}${prefix}/share/doc" || die

		local trimmed_size
		trimmed_size=$( get_size "${install_dir}" ) || die
		log_indent_end "done, ${trimmed_size}"
	fi

	derive_install_tag "${tag}" >"${install_dir}/.halcyon-tag" || die
}


archive_install_dir () {
	expect_vars HALCYON_NO_ARCHIVE HALCYON_NO_CLEAN_PRIVATE_STORAGE

	local install_dir
	expect_args install_dir -- "$@"
	expect_existing "${install_dir}/.halcyon-tag"

	if (( HALCYON_NO_ARCHIVE )); then
		return 0
	fi

	local install_tag platform archive_name
	install_tag=$( detect_install_tag "${install_dir}/.halcyon-tag" ) || die
	platform=$( get_tag_platform "${install_tag}" ) || die
	archive_name=$( format_install_archive_name "${install_tag}" ) || die

	log 'Archiving install'

	create_cached_archive "${install_dir}" "${archive_name}" || die
	if ! upload_cached_file "${platform}" "${archive_name}" || (( HALCYON_NO_CLEAN_PRIVATE_STORAGE )); then
		return 0
	fi

	local archive_prefix archive_pattern
	archive_prefix=$( format_install_archive_name_prefix ) || die
	archive_pattern=$( format_install_archive_name_pattern "${install_tag}" ) || die

	delete_matching_private_stored_files "${platform}" "${archive_prefix}" "${archive_pattern}" "${archive_name}" || die
}


validate_install_dir () {
	local tag install_dir
	expect_args tag install_dir -- "$@"

	local install_tag
	install_tag=$( derive_install_tag "${tag}" ) || die
	detect_tag "${install_dir}/.halcyon-tag" "${install_tag//./\.}" || return 1
}


restore_install_dir () {
	local tag install_dir
	expect_args tag install_dir -- "$@"

	local platform archive_name archive_pattern
	platform=$( get_tag_platform "${tag}" ) || die
	archive_name=$( format_install_archive_name "${tag}" ) || die
	archive_pattern=$( format_install_archive_name_pattern "${tag}" ) || die

	log 'Restoring install'

	if ! extract_cached_archive_over "${archive_name}" "${install_dir}" ||
		! validate_install_dir "${tag}" "${install_dir}" >'/dev/null'
	then
		if ! cache_stored_file "${platform}" "${archive_name}" ||
			! extract_cached_archive_over "${archive_name}" "${install_dir}" ||
			! validate_install_dir "${tag}" "${install_dir}" >'/dev/null'
		then
			return 1
		fi
	else
		touch_cached_file "${archive_name}" || die
	fi

	log 'Install restored'
}


install_app () {
	expect_vars HALCYON_BASE HALCYON_ROOT \
		HALCYON_INTERNAL_RECURSIVE

	local tag source_dir install_dir
	expect_args tag source_dir install_dir -- "$@"

	local prefix label install_id label_dir data_dir
	prefix=$( get_tag_prefix "${tag}" ) || die
	label=$( get_tag_label "${tag}" ) || die
	label_dir="${install_dir}${prefix}/.halcyon/${label}"
	expect_existing "${label_dir}/data-dir"
	data_dir=$( <"${label_dir}/data-dir" ) || die

	if [[ "${HALCYON_ROOT}" == '/' ]]; then
		log_begin "Installing app into ${prefix}..."
	else
		log_begin "Installing app into ${HALCYON_ROOT}${prefix}..."
	fi

	# NOTE: When / is read-only, but HALCYON_BASE is not, cp -Rp fails, but cp -R succeeds.
	# Copying .halcyon-tag is avoided for the same reason.

	local saved_tag
	saved_tag=''
	if [[ -f "${install_dir}/.halcyon-tag" ]]; then
		saved_tag=$( get_tmp_file 'halcyon-saved-tag' ) || die
		mv "${install_dir}/.halcyon-tag" "${saved_tag}" || die
	fi

	mkdir -p "${HALCYON_ROOT}" || die
	cp -R "${install_dir}/." "${HALCYON_ROOT}" 2>&1 | quote || die

	log_end 'done'

	if [[ -n "${saved_tag}" ]]; then
		mv "${saved_tag}" "${install_dir}/.halcyon-tag" || die
	fi

	if [[ -f "${source_dir}/.halcyon/post-install-hook" ]]; then
		log 'Executing post-install hook'
		if ! (
			HALCYON_INTERNAL_RECURSIVE=1 \
				"${source_dir}/.halcyon/post-install-hook" \
					"${tag}" "${source_dir}" "${install_dir}" "${data_dir}" 2>&1 | quote
		); then
			die 'Failed to execute post-install hook'
		fi
		log 'Post-install hook executed'
	fi

	log "Installed ${label}"
}
