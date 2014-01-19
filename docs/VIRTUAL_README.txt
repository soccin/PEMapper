URL:http://www.virtualenv.org/en/latest/virtualenv.html

Usage
The basic usage is:

$ virtualenv ENV
This creates ENV/lib/pythonX.X/site-packages, where any libraries you install will go. It also creates ENV/bin/python, which is a Python interpreter that uses this environment. Anytime you use that interpreter (including when a script has #!/path/to/ENV/bin/python in it) the libraries in that environment will be used.

It also installs Setuptools into the environment.


activate script
In a newly created virtualenv there will be a bin/activate shell script. For Windows systems, activation scripts are provided for CMD.exe and Powershell.

On Posix systems you can do:

$ source bin/activate
This will change your $PATH so its first entry is the virtualenv’s bin/ directory. (You have to use source because it changes your shell environment in-place.) This is all it does; it’s purely a convenience. If you directly run a script or the python interpreter from the virtualenv’s bin/ directory (e.g. path/to/env/bin/pip or /path/to/env/bin/python script.py) there’s no need for activation.

After activating an environment you can use the function deactivate to undo the changes to your $PATH.

The activate script will also modify your shell prompt to indicate which environment is currently active. You can disable this behavior, which can be useful if you have your own custom prompt that already displays the active environment name. To do so, set the VIRTUAL_ENV_DISABLE_PROMPT environment variable to any non-empty value before running the activate script.

