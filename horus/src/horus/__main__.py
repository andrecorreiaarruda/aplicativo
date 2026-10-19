"""`python -m horus` e ponto de entrada do executável."""

import sys


def main() -> int:
    from horus.gui.app import main as run

    return run()


if __name__ == "__main__":
    sys.exit(main())
