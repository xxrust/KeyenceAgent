# Variable Editor Notes

Use this reference when MNM import causes missing variables or when reproducing a reference program.

## Required Inventory

Build a variable inventory before editing MNM:

- Global variables and devices.
- Local variables per program.
- FB instances and their data types.
- Arrays, structures, timers, counters, and retained/device-backed variables.
- External device mappings that must match unit configuration.

## Reconstruction Order

1. Register global groups and global variables.
2. Register FB instance variables before program statements that call them.
3. Register local variables for each program through the local-variable view.
4. Re-import or refresh MNM only after variable names and data types are stable.
5. Compile once to reveal missing names, fix all missing variables, then compile again for type and scope errors.

## Error Handling

- A missing variable after MNM import usually means the program body imported but the variable table did not.
- A type mismatch usually means the variable exists in the wrong scope or has an incorrect data type.
- A missing FB type usually means the official FB was not imported or the project already has a conflicting FB name.
- Do not solve missing variables by deleting logic unless the reference logic analysis proves the logic is unnecessary.
