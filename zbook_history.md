# ZBook History: System Setup & Troubleshooting

### Package Management & Initial Setup
```bash
    8  sudoapt update
    9  sudo apt update
   10  ps aux | grep 2314
   11  kill -9 2314
   12  sudo kill -9 2314
   13  ls 
   14  ls/var/lib/apt/lists/
   15  ls /var/lib/apt/lists/
   16  ls /var/lib/apt/lists/lock 
   17  rm/var/lib/apt/lists/lock
   18  sudo rm /var/lib/apt/lists/lock
   19  sudo apt upgrade
```

### Script Execution & Navigation
```bash
    1  xeyes
    2  pwd
    3  cd Downloads/
   22  cd Downloads/
   24  sh pc_rescue_bootstrap.sh 
   25  cd Downloads/
   26  sh pc_rescue_bootstrap.sh 
   50  sh pc_rescue_bootstrap.sh 
   55  sh pc_rescue_bootstrap.sh 
```

### Filesystem & Mount Point Management
```bash
    4  df -h
    5  df -h .
   27  df-h
   28  df -h
   29  ls /media/alan/ventoy
   30  ls /media/alan/
   32  ls -l /media/alan/
   33  ls -l /media/alan/Ventoy/
   34  pushd /media/alan/Ventoy/
   37  pushd /ntfs
   39  mkdir hpzook
   41  mv hpzook hpzbook
   44  chown alan hpzbook/
   45  sudo chown alan hpzbook
   52  df -h
   65  df -h
   66  mkdie /ntfs/GitHub
   67  mkdir /ntfs/GitHub
   68  ln -s /ntfs/GitHub
   71  lsblk
   72  mount | grep -i ntfs
   94  df -h
  100  lsblk
  102  df -h
  103  lsblk
  116  df -h
  122  rm GitHub
  123  ln -s /home/alan/mnt/apelite/files_zbook/GitHub
```

### Tailscale & Network Setup
```bash
   46  tailscale up
   47  sudo tailscale up
   56  tailscale status
   57  ip addr
  141  ip addr
  142  tailscale status
```

### SSHFS & Remote Storage
```bash
   76  sshfs --version
   77  sudo apt update && sudo apt install sshfs
   78  mkdir -p ~/mnt/apelite
   79  sshfs alan@192.168.1.34:/media/alan/home40 ~/mnt/apelite
   80  df -h
   81  ls /home/alan/mnt/apelite
   82  ls ~/.ssh/id_rsa.pub
   83  ssh-keygen -t rsa -b 4096
   84  ssh-copy-id alan@192.168.1.34
   87  ssh alan@192.168.1.34
   92  sudo vi /etc/fstab
   93  sudo mount -a
  108  mount -a
  109  sudo /etc/fuse.conf
  111  sudo touch /etc/fuse.conf
  114  sudo vi /etc/fuse.conf
  115  mount -a
  117  ls -l /home/alan/mnt/apelite
  118  mkdir /home/alan/mnt/apelite/files_zbook
  119  mkdir /home/alan/mnt/apelite/files_zbook/GitHub
  128  mount -a
  134  mount -a
  145  mount -a
```

### System Configuration (Hostname & Grub)
```bash
  130  sudo nano /etc/default/grub
  131  sudo update-grub
  136  sudo hostnamectl set-hostname alan-USB-zbook
  137  sudo sed -i 's/alan-USB-Ventoy/alan-USB-zbook/g' /etc/hosts
  138  exec bash
```

### Git Installation
```bash
   69  sudo apt install git
   70  git
```

### Antigravity Repository Setup
```bash
   95  sudo mkdir -p /etc/apt/keyrings
   96  curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
   97  echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
   98  sudo apt update
```
