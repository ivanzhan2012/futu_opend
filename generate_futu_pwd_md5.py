#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
富途OpenD密码MD5生成工具
用于将明文密码转换为富途OpenD API所需的MD5哈希格式

支持Windows和Linux/macOS系统
"""

import hashlib
import sys
import getpass


def generate_futu_pwd_md5(password):
    """
    生成富途OpenD API所需的MD5密码哈希
    
    Args:
        password (str): 明文密码
        
    Returns:
        str: 32位小写MD5哈希值
    """
    # 创建MD5哈希对象
    md5_hash = hashlib.md5()
    
    # 更新哈希对象（需要将字符串编码为bytes）
    md5_hash.update(password.encode('utf-8'))
    
    # 获取16进制表示的哈希值（小写）
    return md5_hash.hexdigest()


def main():
    """主函数"""
    print("=" * 50)
    print("富途OpenD密码MD5生成工具")
    print("=" * 50)
    
    # 获取密码输入
    if len(sys.argv) > 1:
        # 从命令行参数获取密码
        password = sys.argv[1]
        print(f"密码: {'*' * len(password)}")
    else:
        # 安全输入密码（不显示明文）
        password = getpass.getpass("请输入富途交易密码: ")
    
    if not password:
        print("错误：密码不能为空")
        sys.exit(1)
    
    # 生成MD5哈希
    md5_hash = generate_futu_pwd_md5(password)
    
    # 输出结果
    print("\n" + "=" * 50)
    print("生成结果：")
    print("=" * 50)
    print(f"明文密码长度: {len(password)}")
    print(f"MD5哈希值: {md5_hash}")
    print(f"哈希长度: {len(md5_hash)}位")
    
    # 使用说明
    print("\n" + "=" * 50)
    print("使用方法：")
    print("=" * 50)
    print("1. 将生成的MD5哈希值复制到.env配置文件中：")
    print(f'   FUTU_UNLOCK_PASSWORD="{md5_hash}"')
    print("\n2. 或者在代码中直接使用：")
    print(f'   unlock_password = "{md5_hash}"')
    print("\n3. 命令行使用示例：")
    print("   python generate_futu_pwd_md5.py 你的密码")
    print("   python generate_futu_pwd_md5.py  (交互式输入)")
    
    return md5_hash


if __name__ == "__main__":
    try:
        md5_hash = main()
        sys.exit(0)
    except KeyboardInterrupt:
        print("\n\n用户取消操作")
        sys.exit(1)
    except Exception as e:
        print(f"\n错误：{e}")
        sys.exit(1)