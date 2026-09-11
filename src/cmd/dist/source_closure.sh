#!/bin/sh
set -eu



entry=${1:?usage: source_closure.sh ENTRY OUTPUT}

output=${2:?usage: source_closure.sh ENTRY OUTPUT}

root=${S_SOURCE_ROOT:-$(pwd)}

resolver="$root/misc/tools/s_resolver"

tmp="${output}.tmp.$$"

pkg_index="$tmp.pkg"

trap 'rm -f "$tmp" "$pkg_index" "$tmp.queue" "$tmp.seen"' EXIT HUP INT TERM

find "$root/src" -name '*.s' -type f | while IFS= read -r source_file; do

    pkg=$(sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' "$source_file" | head -n 1)

    if [ -n "$pkg" ]; then

        printf '%s\t%s\n' "$pkg" "$source_file" | sed "s#	$root/#	#"

    fi

done >"$pkg_index"



resolve_module_fallback() {

    module=$1

    module=${module%% as *}

    case "$module" in

        compile.internal.*)

            rest=${module#compile.internal.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/cmd/compile/internal/$dir.s" ]; then

                    printf 'src/cmd/compile/internal/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/cmd/compile/internal/$dir/${dir##*/}.s" ]; then

                    printf 'src/cmd/compile/internal/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

        internal.*)

            rest=${module#internal.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/internal/$dir.s" ]; then

                    printf 'src/internal/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/internal/$dir/${dir##*/}.s" ]; then

                    printf 'src/internal/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

        std.*)

            rest=${module#std.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/std/$dir.s" ]; then

                    printf 'src/std/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/std/$dir/${dir##*/}.s" ]; then

                    printf 'src/std/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

    esac

    path=$(printf '%s' "$module" | tr . /)

    if [ -f "$root/src/$path.s" ]; then

        printf 'src/%s.s\n' "$path"

    elif [ -f "$root/src/$path/${path##*/}.s" ]; then

        printf 'src/%s/%s.s\n' "$path" "${path##*/}"

    else

        package=$module

        while :; do

            found=$(awk -F '\t' -v pkg="$package" '$1 == pkg { print $2; exit }' "$pkg_index")

            if [ -n "$found" ]; then

                printf '%s\n' "$found" | sed "s#^$root/##"

                return 0

            fi

            case "$package" in

                *.*) package=${package%.*} ;;

                *) break ;;

            esac

        done

    fi

}



if [ "${S_USE_RESOLVER:-}" = "1" ] && [ -x "$resolver" ] && "$resolver" "$root" "$entry" | sed "s#^$root/##" | LC_ALL=C sort -u >"$tmp"; then

    mv "$tmp" "$output"

    trap - EXIT HUP INT TERM

    exit 0

fi



queue="$tmp.queue"

seen="$tmp.seen"

: >"$queue"

: >"$seen"

printf '%s\n' "$entry" >>"$queue"

while IFS= read -r source_path; do

    case "$source_path" in

        /*) rel_path=$(printf '%s\n' "$source_path" | sed "s#^$root/##") ;;

        *) rel_path=$source_path ;;

    esac

    if grep -qxF "$rel_path" "$seen" 2>/dev/null; then

        continue

    fi

    printf '%s\n' "$rel_path" >>"$seen"

    [ -f "$root/$rel_path" ] || continue

    sed -n 's/^[[:space:]]*use[[:space:]]\([^[:space:]]*\).*/\1/p' "$root/$rel_path" |

    while IFS= read -r module; do

        resolved=$(resolve_module_fallback "$module")

        if [ -n "$resolved" ]; then

            printf '%s\n' "$resolved" >>"$queue"

        fi

    done

done <"$queue"

LC_ALL=C sort -u "$seen" >"$tmp"

mv "$tmp" "$output"

trap - EXIT HUP INT TERM
