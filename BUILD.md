# Kako kompajlirati e2e.dll za mIRC

## 🔧 Preduslov

### 1. Visual Studio instalacija
- Instaliraj **Visual Studio 2022** (Community edition je besplatna)
- Obavezno označi: **Desktop development with C++**
- U Individual Components dodaj: **MSVC v143 - VS 2022 C++ x64/x86 build tools (Latest)**

### 2. Preuzmi libsodium (x86 - 32-bit)

#### Opcija A: Prebuilt verzija (PREPORUČENO)
1. Idi na https://download.libsodium.org/libsodium/releases/
2. Preuzmi najnoviju **MSVC** verziju, npr: `libsodium-1.0.20-stable-msvc.zip`
3. Ekstraktuj u `C:\libsodium\`
4. Proveri da imaš:
   ```
   C:\libsodium\Win32\Release\v143\static\libsodium.lib
   C:\libsodium\include\sodium.h
   ```

#### Opcija B: Ako imaš drugu lokaciju
- Prilagodi putanje u Visual Studio project properties

---

## 🏗️ Kompajliranje (Command Line - brzo)

### Developer Command Prompt for VS 2022 (x86)
Otvori **x86 Native Tools Command Prompt for VS 2022** i pokreni:

```cmd
cd C:\Users\majst\source\repos\e2e

cl /LD /MT /O2 ^
   /I"C:\libsodium\include" ^
   e2e.c ^
   /link ^
   /DEF:e2e.def ^
   /MACHINE:X86 ^
   C:\libsodium\Win32\Release\v143\static\libsodium.lib ^
   advapi32.lib user32.lib
```

**Značenje flagova:**
- `/LD` - Kompajliraj kao DLL
- `/MT` - Static runtime (CRT uključen u DLL)
- `/O2` - Optimizacija
- `/I` - Include direktorijum za libsodium
- `/DEF` - Module definition file
- `/MACHINE:X86` - 32-bit target (OBAVEZNO za mIRC!)

**Rezultat:**
```
e2e.dll   ← Ovo kopiraj u mIRC folder
e2e.lib   ← Import library (ne treba za mIRC)
```

---

## 🏗️ Kompajliranje (Visual Studio GUI)

### 1. Kreiraj novi projekt
1. Otvori Visual Studio 2022
2. **Create a new project**
3. Odaberi **Dynamic-Link Library (DLL)** → C++
4. Project name: `e2e`
5. Location: `C:\Users\majst\source\repos\`

### 2. Podesi Platform na Win32
1. Gore u toolbar-u, gde piše **x64**, klikni dropdown
2. **Configuration Manager...**
3. Active solution platform → **New...**
4. Type or select: **Win32 (x86)**
5. Copy settings from: **x64**
6. **OK** → **Close**
7. Sada odaberi **Win32** u dropdownu

### 3. Dodaj source files
1. U **Solution Explorer** → desni klik na **Source Files** → **Add** → **Existing Item**
2. Dodaj: `e2e.c` i `e2e.def`

### 4. Project Properties (BITNO!)
Desni klik na projekat → **Properties** → **All Configurations** → **Win32**

#### C/C++ → General
- **Additional Include Directories**: `C:\libsodium\include`

#### C/C++ → Code Generation
- **Runtime Library**: **Multi-threaded (/MT)**

#### Linker → Input
- **Additional Dependencies**: dodaj na kraj:
  ```
  C:\libsodium\Win32\Release\v143\static\libsodium.lib
  advapi32.lib
  ```

#### Linker → Input (drugi deo)
- **Module Definition File**: `e2e.def`

#### Linker → Advanced
- **Target Machine**: **MachineX86 (/MACHINE:X86)**

### 5. Build
1. **Build** → **Build Solution** (Ctrl+Shift+B)
2. DLL će biti u: `C:\Users\majst\source\repos\e2e\Win32\Release\e2e.dll`

---

## ✅ Provera da li je DLL ispravan

### 1. Proveri da je 32-bit
```cmd
dumpbin /headers e2e.dll | findstr machine
```
**Očekivano:**
```
            8664 machine (x86)
```

### 2. Proveri exports
```cmd
dumpbin /exports e2e.dll
```
**Trebalo bi da vidiš:**
```
    ordinal hint RVA      name
          1    0 00001050 Decrypt
          2    1 00001010 Encrypt
          3    2 000010C0 Test
          4    3 00001090 Version
```

### 3. Proveri dependencies
```cmd
dumpbin /dependents e2e.dll
```
**NE SME sadržati** `libsodium.dll` - sve mora biti statički linkovano!

---

## 📦 Finalni korak - Kopiraj u mIRC

```cmd
copy e2e.dll "C:\Program Files (x86)\mIRC\e2e.dll"
```

ili gde god već imaš mIRC instaliran.

---

## 🐛 Troubleshooting

### "Cannot find sodium.h"
- Proveri putanju: `C:\libsodium\include\sodium.h`
- Proveri Include Directories u Project Properties

### "Unresolved external symbol sodium_init"
- Proveri da linker zna za `libsodium.lib`
- Proveri da je putanja do `.lib` file-a tačna

### mIRC kaže "Invalid DLL"
- DLL nije 32-bit → Proveri sa `dumpbin /headers`
- Pogrešan target platform → Mora biti Win32, ne x64

### "MSVCR143.dll missing" greška
- Runtime nije statički linkovan
- Promeni Runtime Library na `/MT` u Project Properties

---

## 🎯 Sledeći koraci

Kada uspeš da build-uješ DLL, testiraćeš u mIRC:
```mirc
//echo -a $dll(e2e.dll, Test, hello world)
```

Ako vidiš: `e2e.dll OK - received: hello world` → **Radi savršeno!** ✅
