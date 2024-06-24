#!/bin/bash

set -eu
set -o pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "$(readlink -f ${BASH_SOURCE[0]})" )" &> /dev/null && pwd )

e() {
	echo "$@"
	"$@"
}

# Path to install the environment to
: ${NGMOENVS_ENVDIR:="${NGMOENVS_BASEDIR}/envs/${ENVIRONMENT}"}
export NGMOENVS_ENVDIR

# Path to base of this repo
export NGMOENVS_DEFS=${SCRIPT_DIR}/..

# Conda executable being used
: ${CONDA_EXE:=conda}
export CONDA_EXE

# Path to environment definition
export ENVDEFS="${NGMOENVS_DEFS}/environments/${ENVIRONMENT}"
if [[ ! -d "$ENVDEFS" ]]; then
	echo "Enviornment '$ENVIRONMENT' not found"
	exit 1
fi

ENVDIR=$NGMOENVS_ENVDIR
mkdir -p "$ENVDIR"

# Install conda enviornment
if [[ -f "$ENVDEFS/conda.yaml" ]]; then
	# Build any required packages
	"$SCRIPT_DIR/build-conda-packages.sh"

	# Build the environment
	e $CONDA_EXE env create --yes --prefix "$ENVDIR/conda" --file "$ENVDEFS/conda.yaml"
fi

# Install spack environment
if [[ -f "$ENVDEFS/spack.yaml" ]]; then
	if [[ ! -f "$ENVDIR/spack/spack.yaml" ]]; then
		# Create the environment if it doesn't exist
		e spack env create --dir "$ENVDIR/spack" "$ENVDEFS/spack.yaml"
	else
		# Environment exists, copy in def file
		cp "$ENVDEFS/spack.yaml" "$ENVDIR/spack/spack.yaml"
	fi

	# Activate the environment
	e spack env activate "$ENVDIR/spack"
	
	# Add the local packages if they're not already available
	e spack repo add "$NGMOENVS_DEFS/packages/spack" || true

	# Add site config
	if [[ -f "$SCRIPT_DIR/spack-config.yaml" ]]; then
		e spack config add --file "$SCRIPT_DIR/spack-config.yaml"
	fi

	# Add compiler and mpi
	spack config add "packages:all:require:'%${NGMOENVS_COMPILER}'"
	spack config add "packages:mpi:require:'${NGMOENVS_MPI}'"
	e spack add "${NGMOENVS_COMPILER}"

	# Solve dependencies
	e spack concretize --force --fresh

	# Install everything
	e spack install
fi

mkdir -p "$ENVDIR/bin"

# Post install steps
if [[ -d "$ENVDEFS/etc" ]]; then
	e cp -r "$ENVDEFS/etc" "$ENVDIR"
fi

# Activate script
cat > "$ENVDIR/bin/activate" <<EOF
#!/bin/bash

export NGMOENVS_ENVDIR="$ENVDIR"

eval "$(conda shell.bash activate "\$NGMOENVS_ENVDIR/conda")"
spack env activate "\$NGMOENVS_ENVDIR/spack"

if [[ -f "\$NGMOENVS_ENVDIR/etc/env.activate.sh" ]]; then
	source "\$NGMOENVS_ENVDIR/etc/env.activate.sh"
fi

alias deactivate="source \$NGMOENVS_ENVDIR/bin/deactivate"
EOF

# Deactivate script
cat > "$ENVDIR/bin/deactivate" <<EOF
#!/bin/bash

conda deactivate
spack env deactivate
EOF

# Run script
cat > "$ENVDIR/bin/envrun" <<EOF
#!/bin/bash
# Run a command in the environment

source "$ENVDIR/bin/activate"

eval "\$@"
EOF
chmod +x "$ENVDIR/bin/envrun"

cat <<EOF

Environment installed at

    $ENVDIR/

Run commands in the environment with

    $ENVDIR/bin/envrun \$COMMAND

EOF
