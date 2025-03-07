import { useState } from 'react';
import { 
  Container, 
  Box, 
  Typography, 
  Paper, 
  Avatar, 
  Tabs, 
  Tab, 
  List,
  ListItem,
  ListItemText,
  ListItemAvatar,
  IconButton,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
  Divider
} from '@mui/material';
import { 
  History, 
  Subscriptions, 
  Settings,
  Edit
} from '@mui/icons-material';
import { useAuth } from '../../contexts/AuthContext';
import { Link } from 'react-router-dom';

// Custom TabPanel component
const TabPanel = ({ children, value, index, ...other }) => (
  <div
    role="tabpanel"
    hidden={value !== index}
    id={`profile-tabpanel-${index}`}
    aria-labelledby={`profile-tab-${index}`}
    {...other}
  >
    {value === index && (
      <Box sx={{ p: 3 }}>
        {children}
      </Box>
    )}
  </div>
);

const Profile = () => {
  const [activeTab, setActiveTab] = useState(0);
  const [confirmLogoutOpen, setConfirmLogoutOpen] = useState(false);
  const [confirmClearHistoryOpen, setConfirmClearHistoryOpen] = useState(false);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [newUsername, setNewUsername] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  
  const { currentUser, logout, clearWatchHistory, updateProfile } = useAuth();
  
  const handleTabChange = (event, newValue) => {
    setActiveTab(newValue);
  };
  
  const handleLogout = () => {
    logout();
  };
  
  const handleClearHistory = () => {
    clearWatchHistory();
    setConfirmClearHistoryOpen(false);
  };
  
  const handleEditDialogOpen = () => {
    setNewUsername(currentUser.username);
    setEditDialogOpen(true);
  };
  
  const handleEditDialogClose = () => {
    setEditDialogOpen(false);
    setError('');
    setSuccess('');
  };
  
  const handleUpdateProfile = async () => {
    try {
      setError('');
      setSuccess('');
      
      if (!newUsername.trim()) {
        return setError('Username cannot be empty');
      }
      
      await updateProfile({ username: newUsername.trim() });
      setSuccess('Profile updated successfully');
      
      // Close dialog after a short delay
      setTimeout(() => {
        handleEditDialogClose();
      }, 1500);
    } catch (error) {
      setError(error.message);
    }
  };
  
  // Format date to readable string
  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };
  
  return (
    <Container maxWidth="md" sx={{ py: 4 }}>
      <Paper 
        elevation={3} 
        sx={{ 
          p: 3, 
          backgroundColor: 'var(--card-bg)',
          border: '1px solid var(--border-color)',
          borderRadius: '12px'
        }}
      >
        {/* Profile Header */}
        <Box sx={{ 
          display: 'flex', 
          alignItems: 'center', 
          gap: 2, 
          mb: 4 
        }}>
          <Avatar 
            src={currentUser.profilePicture}
            alt={currentUser.username}
            sx={{ 
              width: 80, 
              height: 80,
              border: '2px solid var(--primary-color)'
            }}
          />
          
          <Box sx={{ flex: 1 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
              <Typography variant="h4" color="var(--text-primary)">
                {currentUser.username}
              </Typography>
              
              <IconButton 
                onClick={handleEditDialogOpen}
                size="small"
                sx={{ 
                  color: 'var(--text-secondary)',
                  '&:hover': { color: 'var(--primary-color)' }
                }}
              >
                <Edit fontSize="small" />
              </IconButton>
            </Box>
            
            <Typography variant="body2" color="var(--text-secondary)">
              Joined {formatDate(currentUser.createdAt)}
            </Typography>
          </Box>
        </Box>
        
        {/* Profile Tabs */}
        <Box sx={{ borderBottom: 1, borderColor: 'var(--border-color)' }}>
          <Tabs 
            value={activeTab} 
            onChange={handleTabChange}
            sx={{
              '& .MuiTab-root': {
                color: 'var(--text-secondary)',
                '&.Mui-selected': {
                  color: 'var(--primary-color)'
                }
              },
              '& .MuiTabs-indicator': {
                backgroundColor: 'var(--primary-color)'
              }
            }}
          >
            <Tab 
              icon={<History />} 
              label="Watch History" 
              iconPosition="start"
            />
            <Tab 
              icon={<Subscriptions />} 
              label="Subscriptions" 
              iconPosition="start"
            />
            <Tab 
              icon={<Settings />} 
              label="Settings" 
              iconPosition="start"
            />
          </Tabs>
        </Box>
        
        {/* Watch History Tab */}
        <TabPanel value={activeTab} index={0}>
          {currentUser.watchHistory?.length > 0 ? (
            <List sx={{ p: 0 }}>
              {currentUser.watchHistory.map((video, index) => (
                <Box key={`${video.videoId}-${index}`}>
                  {index > 0 && <Divider sx={{ borderColor: 'var(--border-color)' }} />}
                  <ListItem 
                    component={Link}
                    to={`/video/${video.videoId}`}
                    sx={{
                      display: 'flex',
                      gap: 2,
                      py: 2,
                      color: 'inherit',
                      textDecoration: 'none',
                      '&:hover': {
                        backgroundColor: 'rgba(255, 0, 0, 0.08)'
                      }
                    }}
                  >
                    <Box 
                      component="img"
                      src={video.thumbnail}
                      alt={video.title}
                      sx={{ 
                        width: 160,
                        height: 90,
                        borderRadius: '4px',
                        objectFit: 'cover'
                      }}
                    />
                    
                    <Box sx={{ flex: 1 }}>
                      <Typography 
                        variant="subtitle1" 
                        color="var(--text-primary)"
                        sx={{
                          display: '-webkit-box',
                          overflow: 'hidden',
                          WebkitBoxOrient: 'vertical',
                          WebkitLineClamp: 2,
                        }}
                      >
                        {video.title}
                      </Typography>
                      
                      <Typography 
                        variant="body2" 
                        color="var(--text-secondary)"
                        sx={{ mt: 0.5 }}
                      >
                        {video.channelTitle}
                      </Typography>
                      
                      <Typography 
                        variant="body2" 
                        color="var(--text-secondary)"
                        sx={{ mt: 0.5 }}
                      >
                        Watched on {formatDate(video.watchedAt)}
                      </Typography>
                    </Box>
                  </ListItem>
                </Box>
              ))}
            </List>
          ) : (
            <Box 
              sx={{ 
                display: 'flex', 
                flexDirection: 'column', 
                alignItems: 'center',
                justifyContent: 'center',
                py: 8,
                color: 'var(--text-secondary)'
              }}
            >
              <History sx={{ fontSize: 60, mb: 2, opacity: 0.7 }} />
              <Typography variant="h6">No watch history</Typography>
              <Typography variant="body2" sx={{ mt: 1 }}>
                Videos you watch will appear here
              </Typography>
            </Box>
          )}
        </TabPanel>
        
        {/* Subscriptions Tab */}
        <TabPanel value={activeTab} index={1}>
          {currentUser.subscriptions?.length > 0 ? (
            <List sx={{ p: 0 }}>
              {currentUser.subscriptions.map((subscription, index) => (
                <Box key={`${subscription.channelId}-${index}`}>
                  {index > 0 && <Divider sx={{ borderColor: 'var(--border-color)' }} />}
                  <ListItem 
                    component={Link}
                    to={`/channel/${subscription.channelId}`}
                    sx={{
                      display: 'flex',
                      gap: 2,
                      py: 2,
                      color: 'inherit',
                      textDecoration: 'none',
                      '&:hover': {
                        backgroundColor: 'rgba(255, 0, 0, 0.08)'
                      }
                    }}
                  >
                    <ListItemAvatar>
                      <Avatar 
                        src={subscription.channelThumbnail}
                        alt={subscription.channelTitle}
                      />
                    </ListItemAvatar>
                    
                    <ListItemText
                      primary={
                        <Typography color="var(--text-primary)">
                          {subscription.channelTitle}
                        </Typography>
                      }
                      secondary={
                        <Typography 
                          variant="body2" 
                          color="var(--text-secondary)"
                          sx={{ mt: 0.5 }}
                        >
                          Subscribed on {formatDate(subscription.subscribedAt)}
                        </Typography>
                      }
                    />
                  </ListItem>
                </Box>
              ))}
            </List>
          ) : (
            <Box 
              sx={{ 
                display: 'flex', 
                flexDirection: 'column', 
                alignItems: 'center',
                justifyContent: 'center',
                py: 8,
                color: 'var(--text-secondary)'
              }}
            >
              <Subscriptions sx={{ fontSize: 60, mb: 2, opacity: 0.7 }} />
              <Typography variant="h6">No subscriptions</Typography>
              <Typography variant="body2" sx={{ mt: 1 }}>
                Channels you subscribe to will appear here
              </Typography>
            </Box>
          )}
        </TabPanel>
        
        {/* Settings Tab */}
        <TabPanel value={activeTab} index={2}>
          <Typography variant="h6" color="var(--text-primary)" gutterBottom>
            Account Settings
          </Typography>
          
          <List>
            <ListItem>
              <ListItemText
                primary={
                  <Typography color="var(--text-primary)">
                    Username
                  </Typography>
                }
                secondary={
                  <Typography variant="body2" color="var(--text-secondary)">
                    {currentUser.username}
                  </Typography>
                }
              />
              <Button
                startIcon={<Edit />}
                onClick={handleEditDialogOpen}
                sx={{ 
                  color: 'var(--text-secondary)',
                  '&:hover': { color: 'var(--primary-color)' }
                }}
              >
                Edit
              </Button>
            </ListItem>
          </List>
        </TabPanel>
      </Paper>
      
      {/* Logout Confirmation Dialog */}
      <Dialog
        open={confirmLogoutOpen}
        onClose={() => setConfirmLogoutOpen(false)}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Confirm Logout
        </DialogTitle>
        <DialogContent>
          <Typography color="var(--text-secondary)">
            Are you sure you want to log out?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={() => setConfirmLogoutOpen(false)}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleLogout}
            color="error"
            variant="contained"
          >
            Logout
          </Button>
        </DialogActions>
      </Dialog>
      
      {/* Clear History Confirmation Dialog */}
      <Dialog
        open={confirmClearHistoryOpen}
        onClose={() => setConfirmClearHistoryOpen(false)}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Clear Watch History
        </DialogTitle>
        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            This action cannot be undone.
          </Alert>
          <Typography color="var(--text-secondary)">
            Are you sure you want to clear your entire watch history?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={() => setConfirmClearHistoryOpen(false)}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleClearHistory}
            color="error"
            variant="contained"
          >
            Clear History
          </Button>
        </DialogActions>
      </Dialog>
      
      {/* Edit Profile Dialog */}
      <Dialog 
        open={editDialogOpen} 
        onClose={handleEditDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Edit Profile
        </DialogTitle>
        <DialogContent>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}
          
          {success && (
            <Alert severity="success" sx={{ mb: 2 }}>
              {success}
            </Alert>
          )}
          
          <TextField
            autoFocus
            margin="dense"
            label="Username"
            fullWidth
            variant="outlined"
            value={newUsername}
            onChange={(e) => setNewUsername(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleEditDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleUpdateProfile}
            variant="contained"
            sx={{
              backgroundColor: 'var(--primary-color)',
              '&:hover': {
                backgroundColor: 'var(--primary-color-dark)',
              }
            }}
          >
            Save
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default Profile; 