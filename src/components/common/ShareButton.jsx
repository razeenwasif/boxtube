import { useState } from 'react';
import PropTypes from 'prop-types';
import { 
  Button, 
  IconButton, 
  Menu, 
  MenuItem, 
  ListItemIcon, 
  ListItemText,
  Snackbar,
  Alert,
  Tooltip
} from '@mui/material';
import { 
  Share as ShareIcon, 
  Facebook as FacebookIcon,
  Twitter as TwitterIcon,
  Reddit as RedditIcon,
  LinkedIn as LinkedInIcon,
  Link as LinkIcon,
  WhatsApp as WhatsAppIcon,
  Email as EmailIcon
} from '@mui/icons-material';

/**
 * ShareButton Component
 * Provides a dropdown menu with various sharing options
 * @param {Object} props - Component props
 * @param {string} props.videoId - YouTube video ID
 * @param {string} props.title - Video title
 * @param {boolean} props.isIconButton - Whether to display as an icon button or regular button
 */
const ShareButton = ({ videoId, title, isIconButton = false }) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const [snackbarOpen, setSnackbarOpen] = useState(false);
  
  const open = Boolean(anchorEl);
  
  const handleClick = (event) => {
    setAnchorEl(event.currentTarget);
  };
  
  const handleClose = () => {
    setAnchorEl(null);
  };

  const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
  const encodedUrl = encodeURIComponent(videoUrl);
  const encodedTitle = encodeURIComponent(title);
  
  const shareOptions = [
    {
      name: 'Facebook',
      icon: <FacebookIcon />,
      url: `https://www.facebook.com/sharer/sharer.php?u=${encodedUrl}`
    },
    {
      name: 'Twitter',
      icon: <TwitterIcon />,
      url: `https://twitter.com/intent/tweet?url=${encodedUrl}&text=${encodedTitle}`
    },
    {
      name: 'Reddit',
      icon: <RedditIcon />,
      url: `https://www.reddit.com/submit?url=${encodedUrl}&title=${encodedTitle}`
    },
    {
      name: 'LinkedIn',
      icon: <LinkedInIcon />,
      url: `https://www.linkedin.com/sharing/share-offsite/?url=${encodedUrl}`
    },
    {
      name: 'WhatsApp',
      icon: <WhatsAppIcon />,
      url: `https://api.whatsapp.com/send?text=${encodedTitle}%20${encodedUrl}`
    }
  ];
  
  const copyToClipboard = () => {
    navigator.clipboard.writeText(videoUrl)
      .then(() => {
        setSnackbarOpen(true);
        handleClose();
      })
      .catch(err => {
        console.error('Failed to copy: ', err);
      });
  };
  
  const handleShare = (url) => {
    window.open(url, '_blank', 'noopener,noreferrer');
    handleClose();
  };
  
  const handleEmailShare = () => {
    const mailtoLink = `mailto:?subject=${encodedTitle}&body=Check out this video: ${encodedUrl}`;
    window.location.href = mailtoLink;
    handleClose();
  };
  
  const handleSnackbarClose = (event, reason) => {
    if (reason === 'clickaway') {
      return;
    }
    setSnackbarOpen(false);
  };
  
  const buttonProps = {
    'aria-controls': open ? 'share-menu' : undefined,
    'aria-haspopup': 'true',
    'aria-expanded': open ? 'true' : undefined,
    onClick: handleClick,
    sx: { 
      color: 'var(--text-primary)',
      '&:hover': { 
        color: 'var(--primary-color)',
        backgroundColor: 'rgba(255, 0, 0, 0.08)'
      }
    }
  };
  
  return (
    <>
      {isIconButton ? (
        <Tooltip title="Share">
          <IconButton {...buttonProps} size="medium">
            <ShareIcon />
          </IconButton>
        </Tooltip>
      ) : (
        <Button 
          {...buttonProps}
          startIcon={<ShareIcon />}
          variant="outlined"
          size="small"
          sx={{
            ...buttonProps.sx,
            borderColor: 'var(--border-color)',
            '&:hover': {
              ...buttonProps.sx['&:hover'],
              borderColor: 'var(--primary-color)'
            }
          }}
        >
          Share
        </Button>
      )}
      
      <Menu
        id="share-menu"
        anchorEl={anchorEl}
        open={open}
        onClose={handleClose}
        MenuListProps={{
          'aria-labelledby': 'share-button',
        }}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
            mt: 1
          }
        }}
      >
        {shareOptions.map((option) => (
          <MenuItem 
            key={option.name} 
            onClick={() => handleShare(option.url)}
            sx={{ 
              color: 'var(--text-primary)',
              '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
            }}
          >
            <ListItemIcon sx={{ color: 'var(--primary-color)' }}>
              {option.icon}
            </ListItemIcon>
            <ListItemText>{option.name}</ListItemText>
          </MenuItem>
        ))}
        
        <MenuItem 
          onClick={handleEmailShare}
          sx={{ 
            color: 'var(--text-primary)',
            '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
          }}
        >
          <ListItemIcon sx={{ color: 'var(--primary-color)' }}>
            <EmailIcon />
          </ListItemIcon>
          <ListItemText>Email</ListItemText>
        </MenuItem>
        
        <MenuItem 
          onClick={copyToClipboard}
          sx={{ 
            color: 'var(--text-primary)',
            '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
          }}
        >
          <ListItemIcon sx={{ color: 'var(--primary-color)' }}>
            <LinkIcon />
          </ListItemIcon>
          <ListItemText>Copy Link</ListItemText>
        </MenuItem>
      </Menu>
      
      <Snackbar
        open={snackbarOpen}
        autoHideDuration={3000}
        onClose={handleSnackbarClose}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert 
          onClose={handleSnackbarClose} 
          severity="success" 
          variant="filled"
          sx={{ width: '100%' }}
        >
          Link copied to clipboard!
        </Alert>
      </Snackbar>
    </>
  );
};

ShareButton.propTypes = {
  videoId: PropTypes.string.isRequired,
  title: PropTypes.string.isRequired,
  isIconButton: PropTypes.bool
};

export default ShareButton; 